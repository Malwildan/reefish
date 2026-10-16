package nelayan

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"nelayan-route/internal/domain/weather"
)

type fakeStore struct {
	replies map[string]string
	errs    map[string]error
	calls   map[string]any
}

func (f *fakeStore) Call(_ context.Context, fn string, args any) (json.RawMessage, error) {
	if f.calls == nil {
		f.calls = map[string]any{}
	}
	f.calls[fn] = args
	if err := f.errs[fn]; err != nil {
		return nil, err
	}
	return json.RawMessage(f.replies[fn]), nil
}

type fakeWeather struct {
	err  error
	from time.Time
	n    int
}

func (f *fakeWeather) Point(_ context.Context, lat, lng float64, from time.Time, hours int) (weather.Location, []weather.Hour, error) {
	f.from, f.n = from, hours
	if f.err != nil {
		return weather.Location{}, nil, f.err
	}
	w, wave := 9.0, 1.0
	return weather.Location{Lat: lat, Lng: lng}, []weather.Hour{
		{Time: "2026-10-16T05:00:00Z", WindSpeedMs: &w, WaveHeightM: &wave},
		{Time: "2026-10-16T06:00:00Z", WindSpeedMs: &w, WaveHeightM: &wave},
	}, nil
}

const context0 = `{"cached":null,"for_date":"2026-10-17","window_start":"2026-10-16T21:30:00+00:00",
"boat":{"home_port":{"lat":-8.43,"lng":112.68}},
"stats":{"fuel_per_km":0.5,"avg_catch_kg":40,"baseline_fuel_liters":25},
"config":{"default_fuel_per_km":1.0,"departure_time":"04:30","return_time":"11:00"},
"candidates":[{"grid_id":"X1_Y1","lat":-8.5,"lng":112.7,"dist_m":10000,"potential_score":0.8,"zone":{"status":"normal"}}],
"habitual":null}`

func (f *fakeWeather) Area(_ context.Context, pts []weather.Location, at time.Time) ([]weather.Hour, error) {
	f.from, f.n = at, len(pts)
	if f.err != nil {
		return nil, f.err
	}
	w, wave := 11.0, 0.5
	hs := make([]weather.Hour, len(pts))
	for i := range hs {
		hs[i] = weather.Hour{WindSpeedMs: &w, WaveHeightM: &wave}
	}
	return hs, nil
}

func TestWeatherArea(t *testing.T) {
	now := func() time.Time { return time.Date(2026, 10, 16, 5, 42, 0, 0, time.UTC) }
	st := &fakeStore{replies: map[string]string{"api_heatmap_version": `{"heatmap_version":3}`}}
	fw := &fakeWeather{}
	area, err := Service{Store: st, Forecast: fw, Now: now}.WeatherArea(context.Background(), "", "3")
	if err != nil {
		t.Fatal(err)
	}
	if fw.n != 25 || area.ForecastTime != "2026-10-16T08:00:00Z" || len(area.Points) != 25 {
		t.Fatalf("n=%d area=%+v", fw.n, area)
	}
	p0 := area.Points[0]
	// first sample sits half a step inside the south-west corner of the pilot bbox
	if p0.CellKey != "c00_00" || p0.Lat != -9.15+0.08 || p0.Risk != "high" {
		t.Errorf("point 0 = %+v", p0)
	}
	for _, bad := range []struct{ bbox, hours string }{{"1,2,3", ""}, {"113,-8,112,-9", ""}, {"", "49"}, {"", "-1"}} {
		var e *Error
		if _, err := (Service{Store: st, Forecast: fw}).WeatherArea(context.Background(), bad.bbox, bad.hours); !errors.As(err, &e) || e.Code != "VALIDATION_ERROR" {
			t.Errorf("%v: %v", bad, err)
		}
	}
	var e *Error
	if _, err := (Service{Store: st, Forecast: &fakeWeather{err: errors.New("down")}}).WeatherArea(context.Background(), "", ""); !errors.As(err, &e) || e.Code != "WEATHER_UNAVAILABLE" {
		t.Errorf("weather down: %v", err)
	}
}

func TestRecommendationsReturnsCached(t *testing.T) {
	st := &fakeStore{replies: map[string]string{"api_rec_context": `{"cached":{"items":[]}}`}}
	got, err := Service{Store: st, Forecast: &fakeWeather{}}.Recommendations(context.Background(), "", false)
	if err != nil || string(got) != `{"items":[]}` {
		t.Fatalf("got %s, %v", got, err)
	}
	if _, saved := st.calls["api_save_recommendations"]; saved {
		t.Error("cached set must not be regenerated")
	}
}

func TestRecommendationsRanksAndSaves(t *testing.T) {
	st := &fakeStore{replies: map[string]string{"api_rec_context": context0, "api_save_recommendations": `{"ok":true}`}}
	fw := &fakeWeather{}
	got, err := Service{Store: st, Forecast: fw}.Recommendations(context.Background(), "2026-10-17", true)
	if err != nil || string(got) != `{"ok":true}` {
		t.Fatalf("got %s, %v", got, err)
	}
	if fw.n != 8 || !fw.from.Equal(time.Date(2026, 10, 16, 21, 30, 0, 0, time.UTC)) {
		t.Errorf("weather window from %v hours %d", fw.from, fw.n)
	}
	b, _ := json.Marshal(st.calls["api_save_recommendations"])
	var saved struct {
		P struct {
			ForDate     string           `json:"for_date"`
			Items       []map[string]any `json:"items"`
			Unavailable []map[string]any `json:"unavailable_types"`
		} `json:"p"`
	}
	if err := json.Unmarshal(b, &saved); err != nil {
		t.Fatal(err)
	}
	if saved.P.ForDate != "2026-10-17" || len(saved.P.Items) != 3 || len(saved.P.Unavailable) != 1 {
		t.Fatalf("saved %s", b)
	}
	// 10 km out and back at 0.5 L/km, weather factor 1.25 (wind 9, wave 1)
	if saved.P.Items[0]["predicted_fuel_liters"] != 12.5 {
		t.Errorf("fuel = %v", saved.P.Items[0]["predicted_fuel_liters"])
	}
	ws, _ := saved.P.Items[0]["weather_summary"].(map[string]any)
	if ws["risk"] != "medium" {
		t.Errorf("weather_summary = %v", saved.P.Items[0]["weather_summary"])
	}
	if args := st.calls["api_rec_context"].(map[string]any); args["p_for_date"] != "2026-10-17" || args["p_refresh"] != true {
		t.Errorf("context args %v", args)
	}
}

func TestRecommendationsWithoutWeather(t *testing.T) {
	st := &fakeStore{replies: map[string]string{"api_rec_context": context0, "api_save_recommendations": `{}`}}
	if _, err := (Service{Store: st, Forecast: &fakeWeather{err: errors.New("down")}}).Recommendations(context.Background(), "", false); err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(st.calls["api_save_recommendations"])
	var saved struct {
		P struct {
			Items []map[string]any `json:"items"`
		} `json:"p"`
	}
	_ = json.Unmarshal(b, &saved)
	if saved.P.Items[0]["predicted_fuel_liters"] != 10.0 || saved.P.Items[0]["weather_summary"] != nil {
		t.Errorf("items %v", saved.P.Items[0])
	}
}

func TestRecommendationsErrors(t *testing.T) {
	var e *Error
	_, err := Service{Store: &fakeStore{}}.Recommendations(context.Background(), "17-10-2026", false)
	if !errors.As(err, &e) || e.Code != "VALIDATION_ERROR" {
		t.Errorf("bad date: %v", err)
	}
	st := &fakeStore{errs: map[string]error{"api_rec_context": &Error{Code: "ONBOARDING_REQUIRED"}}}
	_, err = Service{Store: st}.Recommendations(context.Background(), "", false)
	if !errors.As(err, &e) || e.Code != "ONBOARDING_REQUIRED" {
		t.Errorf("store error not passed through: %v", err)
	}
}

func TestWeather(t *testing.T) {
	now := func() time.Time { return time.Date(2026, 10, 16, 5, 42, 0, 0, time.UTC) }
	st := &fakeStore{replies: map[string]string{"api_in_pilot": "true"}}
	fw := &fakeWeather{}
	rep, err := Service{Store: st, Forecast: fw, Now: now}.Weather(context.Background(), "-8.4", "112.6", "")
	if err != nil {
		t.Fatal(err)
	}
	if fw.n != 25 || !fw.from.Equal(time.Date(2026, 10, 16, 5, 0, 0, 0, time.UTC)) {
		t.Errorf("window from %v hours %d", fw.from, fw.n)
	}
	if rep.Current.Time != "2026-10-16T05:00:00Z" || len(rep.Hourly) != 1 || rep.Current.Risk != "medium" || rep.Warnings == nil {
		t.Errorf("report %+v", rep)
	}

	cases := []struct{ lat, lng, hours, code string }{
		{"x", "112", "", "VALIDATION_ERROR"},
		{"-8", "200", "", "VALIDATION_ERROR"},
		{"-8", "112", "49", "VALIDATION_ERROR"},
	}
	for _, c := range cases {
		var e *Error
		if _, err := (Service{Store: st, Forecast: fw}).Weather(context.Background(), c.lat, c.lng, c.hours); !errors.As(err, &e) || e.Code != c.code {
			t.Errorf("%v: got %v", c, err)
		}
	}

	var e *Error
	out := &fakeStore{replies: map[string]string{"api_in_pilot": "false"}}
	if _, err := (Service{Store: out, Forecast: fw}).Weather(context.Background(), "-8", "112", ""); !errors.As(err, &e) || e.Code != "OUT_OF_PILOT" {
		t.Errorf("out of pilot: %v", err)
	}
	if _, err := (Service{Store: st, Forecast: &fakeWeather{err: errors.New("down")}}).Weather(context.Background(), "-8", "112", ""); !errors.As(err, &e) || e.Code != "WEATHER_UNAVAILABLE" {
		t.Errorf("weather down: %v", err)
	}
}
