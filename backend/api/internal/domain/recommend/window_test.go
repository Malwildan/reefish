package recommend

import (
	"testing"

	"nelayan-route/internal/domain/weather"
)

func hoursWithRisk(risks ...string) []weather.Hour {
	hs := make([]weather.Hour, len(risks))
	for i, r := range risks {
		hs[i].Risk = r
	}
	return hs
}

func TestBestWindow(t *testing.T) {
	cases := []struct {
		name        string
		risks       []string
		length, max int
		start       int
		risk        string
		ok          bool
	}{
		{"calm from the start", []string{"low", "low", "low", "low"}, 2, 2, 0, "low", true},
		{"storm early moves departure", []string{"high", "medium", "low", "low", "low"}, 2, 3, 2, "low", true},
		{"unknown beats high but not medium", []string{"high", "unknown", "unknown", "medium", "medium"}, 2, 3, 3, "medium", true},
		{"ties keep the earliest", []string{"medium", "medium", "medium"}, 2, 1, 0, "medium", true},
		{"maxStart caps the search", []string{"high", "high", "low", "low"}, 2, 1, 0, "high", true},
		{"no full window", []string{"low"}, 2, 3, -1, "", false},
	}
	for _, c := range cases {
		start, risk, ok := BestWindow(hoursWithRisk(c.risks...), c.length, c.max)
		if start != c.start || risk != c.risk || ok != c.ok {
			t.Errorf("%s: got %d %q %v, want %d %q %v", c.name, start, risk, ok, c.start, c.risk, c.ok)
		}
	}
	if WorstRisk(nil) != "unknown" {
		t.Error("empty window must be unknown")
	}
}
