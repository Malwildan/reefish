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
	Cached  json.RawMessage `json:"cached"`
	ForDate string          `json:"for_date"`
	Boat    struct {
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
	// shortcut: one forecast at the home port for the whole area. Without a forecast the factor stays 1,
	// weather_summary is null and the configured departure/return times are kept.
	var ws *summary
	var dep, ret string
	if win, ok := s.tripWindow(rc); ok {
		// a slow Open-Meteo must not fail the recommendations: after 6 s they are ranked without weather
		wctx, cancel := context.WithTimeout(ctx, 6*time.Second)
		_, hs, err := s.Forecast.Point(wctx, rc.Boat.HomePort.Lat, rc.Boat.HomePort.Lng, win.from, win.fetch)
		cancel()
		if err == nil {
			weather.Enrich(hs)
			if start, _, ok := recommend.BestWindow(hs, win.length, win.maxStart); ok {
				trip := hs[start : start+win.length]
				ws = summarise(trip)
				in.WeatherFactor = recommend.WeatherFactor(maxOf(trip, func(h weather.Hour) *float64 { return h.WindSpeedMs }),
					maxOf(trip, func(h weather.Hour) *float64 { return h.WaveHeightM }))
				depAt := win.from.Add(time.Duration(start) * time.Hour)
				dep, ret = depAt.In(wib).Format("15:04"), depAt.Add(win.duration).In(wib).Format("15:04")
			}
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
		"departure_time": nullable(dep), "return_time": nullable(ret),
	}})
}

var wib = time.FixedZone("WIB", 7*3600)

// Departures are searched between these WIB hours (AGENTS.md 10.4: lowest-risk window in the forecast).
const earliestDepartureHour, latestDepartureHour = 3, 8

type tripWindow struct {
	from     time.Time     // earliest departure, UTC
	duration time.Duration // configured trip length (return - departure)
	length   int           // forecast hours one trip touches
	maxStart int           // last departure offset in hours
	fetch    int           // forecast hours to request
}

// tripWindow derives the departure search for rc.ForDate from the configured trip length.
func (s Service) tripWindow(rc recContext) (tripWindow, bool) {
	dep, err1 := time.Parse("15:04", rc.Config.DepartureTime)
	ret, err2 := time.Parse("15:04", rc.Config.ReturnTime)
	day, err3 := time.ParseInLocation(time.DateOnly, rc.ForDate, wib)
	if err1 != nil || err2 != nil || err3 != nil {
		return tripWindow{}, false
	}
	d := ret.Sub(dep)
	if d <= 0 {
		d += 24 * time.Hour
	}
	w := tripWindow{
		from:     day.Add(earliestDepartureHour * time.Hour).UTC(),
		duration: d,
		length:   int(math.Ceil(d.Hours())) + 1,
		maxStart: latestDepartureHour - earliestDepartureHour,
	}
	w.fetch = w.maxStart + w.length
	return w, true
}

func nullable(v string) any {
	if v == "" {
		return nil
	}
	return v
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

func summarise(hs []weather.Hour) *summary {
	h := hs[0]
	return &summary{WindSpeedMs: h.WindSpeedMs, WindDirDeg: h.WindDirDeg, WindDirLabel: h.WindDirLabel,
		WaveHeightM: h.WaveHeightM, TempC: h.TempC, Risk: recommend.WorstRisk(hs)}
}

// Weather is the point forecast for the app and the admin grid panel (AGENTS.md 12.B.8; api_in_pilot accepts
// both roles). hours "" defaults to 24, max 48.
func (s Service) Weather(ctx context.Context, latS, lngS, hoursS string) (*weather.Report, error) {
	lat, err := strconv.ParseFloat(latS, 64)
	if err != nil || math.IsNaN(lat) || math.IsInf(lat, 0) || lat < -90 || lat > 90 {
		return nil, invalid("lat", "wajib angka -90 sampai 90")
	}
	lng, err := strconv.ParseFloat(lngS, 64)
	if err != nil || math.IsNaN(lng) || math.IsInf(lng, 0) || lng < -180 || lng > 180 {
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
			ok = err == nil && !math.IsNaN(v) && !math.IsInf(v, 0)
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
	// Authenticate through an RPC present in the deployed nelayan migration prefix.
	// The canonical pilot center is valid even when callers request a custom bbox.
	pilotLat := (aoi[1] + aoi[3]) / 2
	pilotLng := (aoi[0] + aoi[2]) / 2
	raw, err := s.Store.Call(ctx, "api_in_pilot", map[string]any{"p_lat": pilotLat, "p_lng": pilotLng})
	if err != nil {
		return nil, err
	}
	var inPilot bool
	if err := json.Unmarshal(raw, &inPilot); err != nil {
		return nil, err
	}
	if !inPilot {
		return nil, &Error{Code: "OUT_OF_PILOT", Message: "Area pilot tidak tersedia"}
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
