package physics

import (
	"math"
	"testing"
)

func near(t *testing.T, name string, got, want float64) {
	t.Helper()
	if math.Abs(got-want) > 1e-6 {
		t.Errorf("%s = %v, want %v", name, got, want)
	}
}

func TestWindFromCardinals(t *testing.T) {
	// from 0/90/180/270 moves south/west/north/east (spec 15.1)
	want := []Vec{{0, -1}, {-1, 0}, {0, 1}, {1, 0}}
	for i, from := range []float64{0, 90, 180, 270} {
		v := WindVector(1, from)
		near(t, "E", v.E, want[i].E)
		near(t, "N", v.N, want[i].N)
	}
}

func TestCurrentToCardinals(t *testing.T) {
	want := []Vec{{0, 1}, {1, 0}, {0, -1}, {-1, 0}}
	for i, to := range []float64{0, 90, 180, 270} {
		v := VectorTo(1, to)
		near(t, "E", v.E, want[i].E)
		near(t, "N", v.N, want[i].N)
		near(t, "bearing", Bearing(v), to)
	}
}

// Spec 8.8: STW 3 m/s, 500 m edge, current 1 m/s, 6 L/h.
func TestSpecExample(t *testing.T) {
	e := Vec{0, 1}
	cases := []struct {
		name           string
		c              Vec
		sog, dur, fuel float64
	}{
		{"searah", Vec{0, 1}, 4, 125, 0.208333},
		{"berlawanan", Vec{0, -1}, 2, 250, 0.416667},
		{"tegak lurus", Vec{1, 0}, math.Sqrt(8), 176.776695, 0.294628},
	}
	for _, tc := range cases {
		sog, water, err := SolveTrack(e, 3, tc.c)
		if err != nil {
			t.Fatal(tc.name, err)
		}
		near(t, tc.name+" sog", sog, tc.sog)
		near(t, tc.name+" stw", water.Norm(), 3)
		dur := 500 / sog
		if math.Abs(dur-tc.dur) > 1e-5 || math.Abs(6*dur/3600-tc.fuel) > 1e-6 {
			t.Errorf("%s: dur %v fuel %v", tc.name, dur, 6*dur/3600)
		}
	}
}

func TestZeroCurrent(t *testing.T) {
	e := VectorTo(1, 37)
	sog, water, _ := SolveTrack(e, 3, Vec{})
	near(t, "sog", sog, 3)
	near(t, "heading", Bearing(water), 37)
}

func TestCrossCurrentTooStrong(t *testing.T) {
	if _, _, err := SolveTrack(Vec{0, 1}, 3, Vec{3.5, 0}); err != ErrCrossCurrent {
		t.Fatalf("want ErrCrossCurrent, got %v", err)
	}
}

func TestHeadCurrentNoProgress(t *testing.T) {
	sog, _, err := SolveTrack(Vec{0, 1}, 3, Vec{0, -3})
	if err != nil || sog > 0 {
		t.Fatalf("want sog <= 0, got %v %v", sog, err)
	}
}

func TestFuelCurve(t *testing.T) {
	c, err := NewFuelCurve([]CurvePoint{{4, 9.6}, {2, 2.8}, {3, 5.4}})
	if err != nil {
		t.Fatal(err)
	}
	r, _ := c.Rate(2.5)
	near(t, "2.5", r, 4.1)
	r, _ = c.Rate(4)
	near(t, "4", r, 9.6)
	if _, err := c.Rate(4.1); err == nil {
		t.Error("extrapolation must fail")
	}
	single, _ := NewFuelCurve([]CurvePoint{{3, 5.4}})
	if r, err := single.Rate(3); err != nil || r != 5.4 {
		t.Error("single point at its STW must work")
	}
	if _, err := single.Rate(2.9); err == nil {
		t.Error("single point must reject other STW")
	}
}

func TestReserve(t *testing.T) {
	near(t, "fixed wins", Reserve(8, 0.1, 40), 8)
	near(t, "fraction wins", Reserve(8, 0.25, 40), 10)
}
