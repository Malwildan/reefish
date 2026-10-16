package recommend

import "testing"

func f(v float64) *float64 { return &v }

func cells() []Cell {
	return []Cell{
		{GridID: "near_low", Lat: -8.40, Lng: 112.60, DistM: 2000, PotentialScore: f(0.2), Zone: Zone{Status: "normal"}},
		{GridID: "far_high", Lat: -8.60, Lng: 112.90, DistM: 30000, PotentialScore: f(0.9), Zone: Zone{Status: "restricted"}},
		{GridID: "mid_mid", Lat: -8.50, Lng: 112.70, DistM: 8000, PotentialScore: f(0.5), Zone: Zone{Status: "normal"}},
	}
}

func byType(items []Item) map[string]Item {
	m := map[string]Item{}
	for _, it := range items {
		m[it.Type] = it
	}
	return m
}

func TestRankPicksPerType(t *testing.T) {
	items, un := Rank(Input{
		Candidates: cells(), FuelPerKm: 0.8, AvgCatchKg: f(40), BaselineFuelL: f(25), WeatherFactor: 1,
		Habitual: &Cell{GridID: "home", Lat: -8.45, Lng: 112.65, DistM: 5000, Zone: Zone{Status: "normal"}},
	})
	got := byType(items)
	want := map[string]string{"fuel_saving": "near_low", "catch_max": "far_high", "balanced": "mid_mid", "habitual": "home"}
	for typ, grid := range want {
		if got[typ].GridID != grid {
			t.Errorf("%s = %s, want %s", typ, got[typ].GridID, grid)
		}
	}
	if len(un) != 0 || len(items) != 4 || items[0].Type != "fuel_saving" || items[3].Type != "habitual" {
		t.Errorf("order/unavailable wrong: %+v %+v", items, un)
	}
	fs := got["fuel_saving"]
	// 2 km out and back at 0.8 L/km
	if fs.PredictedFuelLiters != 3.2 || fs.FuelEfficiencyPct == nil || *fs.FuelEfficiencyPct != 87.2 {
		t.Errorf("fuel = %v eff = %v", fs.PredictedFuelLiters, fs.FuelEfficiencyPct)
	}
	// lowest potential normalises to 0: catch = 40 * 0.5
	if fs.PredictedCatchKg == nil || *fs.PredictedCatchKg != 20 || *fs.PredictedCatchMin != 14 || *fs.PredictedCatchMax != 26 {
		t.Errorf("catch = %v", fs.PredictedCatchKg)
	}
}

func TestRankReplacesClosedHabitual(t *testing.T) {
	items, _ := Rank(Input{
		Candidates: cells(), FuelPerKm: 1, WeatherFactor: 1,
		Habitual: &Cell{GridID: "closed", Lat: -8.59, Lng: 112.89, Zone: Zone{Status: "rehab", Closed: true}},
	})
	h := byType(items)["habitual"]
	if h.GridID != "far_high" || h.Reason == "Area yang paling sering Anda datangi" {
		t.Errorf("habitual = %+v", h)
	}
	if h.PredictedCatchKg != nil || h.FuelEfficiencyPct != nil {
		t.Errorf("no history must leave predictions nil: %+v", h)
	}
}

func TestRankNoCandidates(t *testing.T) {
	items, un := Rank(Input{FuelPerKm: 1, WeatherFactor: 1})
	if len(items) != 0 || len(un) != 4 || un[3].Type != "habitual" || un[0].ReasonCode != "NO_VALID_CANDIDATE" {
		t.Errorf("items %+v unavailable %+v", items, un)
	}
}

func TestWeatherFactor(t *testing.T) {
	cases := []struct {
		wind, wave *float64
		want       float64
	}{
		{nil, nil, 1},
		{f(3), f(0), 1},
		{f(9), f(1), 1.25},
		{f(30), f(4), 1.5},
	}
	for _, c := range cases {
		if got := WeatherFactor(c.wind, c.wave); got < c.want-1e-9 || got > c.want+1e-9 {
			t.Errorf("WeatherFactor(%v, %v) = %v, want %v", c.wind, c.wave, got, c.want)
		}
	}
}

func TestRankReplacesCriticalHabitual(t *testing.T) {
	items, _ := Rank(Input{
		Candidates: cells(), FuelPerKm: 1, WeatherFactor: 1,
		Habitual: &Cell{GridID: "tired_out", Lat: -8.41, Lng: 112.61, Zone: Zone{Status: "normal"}, Critical: true},
	})
	if h := byType(items)["habitual"]; h.GridID != "near_low" {
		t.Errorf("critical habitual must be replaced by the nearest candidate, got %+v", h)
	}
}
