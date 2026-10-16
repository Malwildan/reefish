// Package nelayan is the computation side of the fisher API: recommendations and weather.
// Plain data endpoints (profile, boat, trips) are Supabase RPCs called by the app directly.
package nelayan

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"nelayan-route/internal/domain/recommend"
	"nelayan-route/internal/domain/weather"
)

// Store calls a Supabase RPC as the current user. A business rule failure is returned as *Error.
type Store interface {
	Call(ctx context.Context, fn string, args any) (json.RawMessage, error)
}

// Forecaster returns hourly conditions at a point for [from, from+hours), or at one hour for many points.
type Forecaster interface {
	Point(ctx context.Context, lat, lng float64, from time.Time, hours int) (weather.Location, []weather.Hour, error)
	Area(ctx context.Context, pts []weather.Location, at time.Time) ([]weather.Hour, error)
}

// Error is the API error body; Code selects the HTTP status in the delivery layer.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
	cause   error
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }
func (e *Error) Unwrap() error { return e.cause }

func invalid(field, msg string) *Error {
	return &Error{Code: "VALIDATION_ERROR", Message: "Parameter tidak valid", Details: map[string]any{"fields": map[string]string{field: msg}}}
}

type Service struct {
	Store    Store
	Forecast Forecaster
	Now      func() time.Time
}

func (s Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

type recContext struct {
	Cached      json.RawMessage `json:"cached"`
	ForDate     string          `json:"for_date"`
	WindowStart time.Time       `json:"window_start"`
	Boat        struct {
		HomePort struct {
			Lat float64 `json:"lat"`
			Lng float64 `json:"lng"`
		} `json:"home_port"`
	} `json:"boat"`
	Stats struct {
		FuelPerKm     *float64 `json:"fuel_per_km"`
		AvgCatchKg    *float64 `json:"avg_catch_kg"`
		BaselineFuelL *float64 `json:"baseline_fuel_liters"`
	} `json:"stats"`
	Config struct {
		DefaultFuelPerKm float64 `json:"default_fuel_per_km"`
		DepartureTime    string  `json:"departure_time"`
		ReturnTime       string  `json:"return_time"`
	} `json:"config"`
	Candidates []recommend.Cell `json:"candidates"`
	Habitual   *recommend.Cell  `json:"habitual"`
}

// summary is the per-item weather_summary: conditions at departure, risk = worst hour of the trip.
type summary struct {
	WindSpeedMs  *float64 `json:"wind_speed_ms"`
	WindDirDeg   *float64 `json:"wind_dir_deg"`
	WindDirLabel *string  `json:"wind_dir_label"`
	WaveHeightM  *float64 `json:"wave_height_m"`
	TempC        *float64 `json:"temp_c"`
	Risk         string   `json:"risk"`
}

// Recommendations returns the cached set for forDate (WIB, "" = today) or ranks and stores a new one.
func (s Service) Recommendations(ctx context.Context, forDate string, refresh bool) (json.RawMessage, error) {
	args := map[string]any{"p_refresh": refresh}
	if forDate != "" {
		if _, err := time.Parse(time.DateOnly, forDate); err != nil {
			return nil, invalid("for_date", "format YYYY-MM-DD")
		}
		args["p_for_date"] = forDate
	}
	raw, err := s.Store.Call(ctx, "api_rec_context", args)
	if err != nil {
		return nil, err
	}
	var rc recContext
	if err := json.Unmarshal(raw, &rc); err != nil {
		return nil, err
	}
	if len(rc.Cached) > 0 && string(rc.Cached) != "null" {
		return rc.Cached, nil
	}

	in := recommend.Input{
		Candidates: rc.Candidates, Habitual: rc.Habitual, AvgCatchKg: rc.Stats.AvgCatchKg,
		BaselineFuelL: rc.Stats.BaselineFuelL, FuelPerKm: rc.Config.DefaultFuelPerKm, WeatherFactor: 1,
	}
	if rc.Stats.FuelPerKm != nil {
		in.FuelPerKm = *rc.Stats.FuelPerKm
	}
	// shortcut: one forecast at the home port for the whole area; on failure the factor stays 1 and
	// weather_summary is null (the set is marked is_fallback either way).
	var ws *summary
	if hours, ok := s.window(rc); ok {
		if _, hs, err := s.Forecast.Point(ctx, rc.Boat.HomePort.Lat, rc.Boat.HomePort.Lng, rc.WindowStart, hours); err == nil && len(hs) > 0 {
			weather.Enrich(hs)
			ws = summarise(hs)
			in.WeatherFactor = recommend.WeatherFactor(maxOf(hs, func(h weather.Hour) *float64 { return h.WindSpeedMs }),
				maxOf(hs, func(h weather.Hour) *float64 { return h.WaveHeightM }))
		}
	}

	items, unavailable := recommend.Rank(in)
	out := make([]map[string]any, len(items))
	for i, it := range items {
		b, _ := json.Marshal(it)
		var m map[string]any
		_ = json.Unmarshal(b, &m)
		m["weather_summary"] = ws
		out[i] = m
	}
	return s.Store.Call(ctx, "api_save_recommendations", map[string]any{"p": map[string]any{
		"for_date": rc.ForDate, "items": out, "unavailable_types": unavailable,
		"fuel_per_km": in.FuelPerKm, "avg_catch_kg": rc.Stats.AvgCatchKg, "baseline_fuel_liters": rc.Stats.BaselineFuelL,
		"model_version": "heuristic-0.1", "is_fallback": true,
	}})
}

// window is the trip length in hours from departure to return time; false when config is unusable.
func (s Service) window(rc recContext) (int, bool) {
	dep, err1 := time.Parse("15:04", rc.Config.DepartureTime)
	ret, err2 := time.Parse("15:04", rc.Config.ReturnTime)
	if err1 != nil || err2 != nil || rc.WindowStart.IsZero() {
		return 0, false
	}
	d := ret.Sub(dep)
	if d <= 0 {
		d += 24 * time.Hour
	}
	return int(math.Ceil(d.Hours())) + 1, true
}

func maxOf(hs []weather.Hour, get func(weather.Hour) *float64) *float64 {
	var m *float64
	for _, h := range hs {
		if v := get(h); v != nil && (m == nil || *v > *m) {
			m = v
		}
	}
	return m
}

var riskRank = map[string]int{"low": 0, "medium": 1, "unknown": 2, "high": 3}

func summarise(hs []weather.Hour) *summary {
	h := hs[0]
	s := &summary{WindSpeedMs: h.WindSpeedMs, WindDirDeg: h.WindDirDeg, WindDirLabel: h.WindDirLabel,
		WaveHeightM: h.WaveHeightM, TempC: h.TempC, Risk: h.Risk}
	for _, x := range hs[1:] {
		if riskRank[x.Risk] > riskRank[s.Risk] {
			s.Risk = x.Risk
		}
	}
	return s
}

// Weather is the point forecast for the app (AGENTS.md 12.B.8). hours "" defaults to 24, max 48.
func (s Service) Weather(ctx context.Context, latS, lngS, hoursS string) (*weather.Report, error) {
	lat, err := strconv.ParseFloat(latS, 64)
	if err != nil || lat < -90 || lat > 90 {
		return nil, invalid("lat", "wajib angka -90 sampai 90")
	}
	lng, err := strconv.ParseFloat(lngS, 64)
	if err != nil || lng < -180 || lng > 180 {
		return nil, invalid("lng", "wajib angka -180 sampai 180")
	}
	hours := 24
	if hoursS != "" {
		if hours, err = strconv.Atoi(hoursS); err != nil || hours < 1 || hours > 48 {
			return nil, invalid("hours", "1 sampai 48")
		}
	}

	raw, err := s.Store.Call(ctx, "api_in_pilot", map[string]any{"p_lat": lat, "p_lng": lng})
	if err != nil {
		return nil, err
	}
	var inPilot bool
	if err := json.Unmarshal(raw, &inPilot); err != nil {
		return nil, err
	}
	if !inPilot {
		return nil, &Error{Code: "OUT_OF_PILOT", Message: "Lokasi di luar area pilot"}
	}

	now := s.now().UTC()
	// +1: the current hour is reported separately from the forecast hours
	loc, hs, err := s.Forecast.Point(ctx, lat, lng, now.Truncate(time.Hour), hours+1)
	if err != nil {
		return nil, &Error{Code: "WEATHER_UNAVAILABLE", Message: "Data cuaca sedang tidak tersedia", cause: err}
	}
	if len(hs) == 0 {
		return nil, &Error{Code: "WEATHER_UNAVAILABLE", Message: "Data cuaca sedang tidak tersedia", cause: errors.New("no hours")}
	}
	warnings := weather.Enrich(hs)
	cur := hs[0]
	if cur.WeatherCode != nil {
		l := weather.Label(*cur.WeatherCode)
		cur.WeatherLabel = &l
	}
	return &weather.Report{Location: loc, FetchedAt: now.Format(time.RFC3339), Current: cur, Hourly: hs[1:], Warnings: warnings}, nil
}

// aoi is the pilot bbox [minLng, minLat, maxLng, maxLat] (guide section 2).
var aoi = [4]float64{112.25, -9.15, 113.10, -8.35}

// areaSide is the lattice size: areaSide x areaSide samples in one Open-Meteo request.
const areaSide = 5

// WeatherArea samples a lattice over bbox ("minLng,minLat,maxLng,maxLat", default pilot) at now+hours
// (AGENTS.md 12.A.4 getWeatherArea; hours 0..48, default 0). Shared by both roles.
func (s Service) WeatherArea(ctx context.Context, bboxS, hoursS string) (*weather.Area, error) {
	bbox := aoi
	if bboxS != "" {
		parts := strings.Split(bboxS, ",")
		ok := len(parts) == 4
		for i := 0; ok && i < 4; i++ {
			v, err := strconv.ParseFloat(strings.TrimSpace(parts[i]), 64)
			ok = err == nil
			bbox[i] = v
		}
		if !ok || bbox[0] >= bbox[2] || bbox[1] >= bbox[3] || bbox[1] < -90 || bbox[3] > 90 || bbox[0] < -180 || bbox[2] > 180 {
			return nil, invalid("bbox", "minLng,minLat,maxLng,maxLat")
		}
	}
	hours := 0
	if hoursS != "" {
		var err error
		if hours, err = strconv.Atoi(hoursS); err != nil || hours < 0 || hours > 48 {
			return nil, invalid("hours", "0 sampai 48")
		}
	}
	// authenticates the caller (any role) before spending an external request
	if _, err := s.Store.Call(ctx, "api_heatmap_version", nil); err != nil {
		return nil, err
	}

	at := s.now().UTC().Truncate(time.Hour).Add(time.Duration(hours) * time.Hour)
	pts := make([]weather.Location, 0, areaSide*areaSide)
	keys := make([]string, 0, areaSide*areaSide)
	for r := 0; r < areaSide; r++ {
		for c := 0; c < areaSide; c++ {
			pts = append(pts, weather.Location{
				Lat: bbox[1] + (float64(r)+0.5)*(bbox[3]-bbox[1])/areaSide,
				Lng: bbox[0] + (float64(c)+0.5)*(bbox[2]-bbox[0])/areaSide,
			})
			keys = append(keys, fmt.Sprintf("c%02d_%02d", r, c))
		}
	}
	hs, err := s.Forecast.Area(ctx, pts, at)
	if err != nil {
		return nil, &Error{Code: "WEATHER_UNAVAILABLE", Message: "Data cuaca sedang tidak tersedia", cause: err}
	}
	weather.Enrich(hs)
	area := &weather.Area{ForecastTime: at.Format(time.RFC3339), Points: make([]weather.AreaPoint, len(hs))}
	for i, h := range hs {
		if h.WeatherCode != nil {
			l := weather.Label(*h.WeatherCode)
			h.WeatherLabel = &l
		}
		area.Points[i] = weather.AreaPoint{CellKey: keys[i], Lat: pts[i].Lat, Lng: pts[i].Lng, Hour: h}
	}
	return area, nil
}
