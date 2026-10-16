package weather

import "testing"

func f(v float64) *float64 { return &v }

func TestRisk(t *testing.T) {
	cases := []struct {
		wind, wave *float64
		want       string
	}{
		{f(4), f(0.8), "low"},
		{f(7.5), f(0.8), "medium"},
		{f(4), f(1.3), "medium"},
		{f(10.1), f(0.5), "high"},
		{f(4), f(2.1), "high"},
		{f(11), nil, "high"},
		{f(4), nil, "unknown"},
		{nil, f(0.5), "unknown"},
		{f(10), f(2), "medium"}, // thresholds are strict
	}
	for _, c := range cases {
		if got := Risk(c.wind, c.wave); got != c.want {
			t.Errorf("Risk(%v, %v) = %s, want %s", c.wind, c.wave, got, c.want)
		}
	}
}

func TestDirLabel(t *testing.T) {
	for deg, want := range map[float64]string{0: "U", 22: "U", 23: "TL", 90: "T", 120: "TG", 180: "S", 270: "B", 337: "BL", 359: "U", -90: "B"} {
		if got := DirLabel(deg); got != want {
			t.Errorf("DirLabel(%v) = %s, want %s", deg, got, want)
		}
	}
}

func TestEnrichMergesHighHours(t *testing.T) {
	hours := []Hour{
		{Time: "2026-10-16T05:00:00Z", WindSpeedMs: f(4), WaveHeightM: f(0.5), WindDirDeg: f(120)},
		{Time: "2026-10-16T06:00:00Z", WindSpeedMs: f(11), WaveHeightM: f(0.5)},
		{Time: "2026-10-16T07:00:00Z", WindSpeedMs: f(4), WaveHeightM: f(2.5)},
		{Time: "2026-10-16T08:00:00Z", WindSpeedMs: f(4), WaveHeightM: f(0.5)},
		{Time: "2026-10-16T09:00:00Z", WindSpeedMs: f(4), WaveHeightM: f(3)},
	}
	w := Enrich(hours)
	if len(w) != 2 {
		t.Fatalf("warnings = %+v, want 2", w)
	}
	if w[0].From != "2026-10-16T06:00:00Z" || w[0].To != "2026-10-16T08:00:00Z" || w[0].Reason != "Angin > 10 m/s, Gelombang > 2 m" {
		t.Errorf("first warning = %+v", w[0])
	}
	if w[1].To != "2026-10-16T10:00:00Z" {
		t.Errorf("second warning = %+v", w[1])
	}
	if hours[0].Risk != "low" || hours[0].WindDirLabel == nil || *hours[0].WindDirLabel != "TG" {
		t.Errorf("hour not enriched: %+v", hours[0])
	}
}
