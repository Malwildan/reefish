package planroute

import (
	"encoding/json"
	"fmt"
	"math"
	"testing"

	"nelayan-route/internal/domain/environment"
	"nelayan-route/internal/domain/routing"
)

const step = 0.0045

func grid(w int) *routing.Grid {
	var cells []routing.Cell
	for x := 0; x < w; x++ {
		cells = append(cells, routing.Cell{ID: fmt.Sprintf("X%d_Y0", x), X: x, Point: routing.Point{Lon: float64(x) * step}})
	}
	return routing.NewGrid(cells)
}

func request(t *testing.T) *Request {
	var r Request
	err := json.Unmarshal([]byte(`{
	  "origin": {"lat": 0, "lon": 0},
	  "destination": {"lat": 0, "lon": 0.018},
	  "return_to": {"lat": 0, "lon": 0},
	  "depart_at": "2026-10-17T03:00:00Z",
	  "latest_return_at": "2026-10-17T09:00:00Z",
	  "vessel": {"stw_min_mps": 2, "stw_max_mps": 4, "fuel_curves": [
	    {"load_class": "light", "points": [{"stw_mps": 2, "rate_lph": 2.8}, {"stw_mps": 3, "rate_lph": 5.4}, {"stw_mps": 4, "rate_lph": 9.6}]},
	    {"load_class": "loaded", "points": [{"stw_mps": 2, "rate_lph": 3.2}, {"stw_mps": 3, "rate_lph": 6.0}, {"stw_mps": 4, "rate_lph": 10.8}]}]},
	  "spot_activity": {"duration_s": 3600, "position_mode": "station_keeping", "fuel_rate_lph": 2.0},
	  "outbound": {"stw_mps": 3, "load_class": "light"},
	  "inbound": {"stw_mps": 3, "load_class": "loaded"},
	  "fuel_budget": {"usable_at_departure_l": 40, "reserve_fixed_l": 8, "reserve_fraction": 0.2},
	  "safety": {"min_progress_mps": 0.5}
	}`), &r)
	if err != nil {
		t.Fatal(err)
	}
	if e := r.Validate(); e != nil {
		t.Fatal(e)
	}
	return &r
}

func TestPlanReconcilesFuel(t *testing.T) {
	r := request(t)
	res, e := compute(r, grid(5), nil, environment.Environment{})
	if e != nil {
		t.Fatal(e)
	}
	s := res.Summary
	d := routing.Distance(r.Origin.point(), r.Destination.point())
	wantOut, wantIn := 5.4*d/3/3600, 6.0*d/3/3600
	if math.Abs(s["estimated_fuel_outbound_l"].(float64)-wantOut) > 1e-9 ||
		math.Abs(s["estimated_fuel_inbound_l"].(float64)-wantIn) > 1e-9 ||
		math.Abs(s["estimated_fuel_total_l"].(float64)-(wantOut+2+wantIn)) > 1e-9 {
		t.Fatalf("fuel does not reconcile: %v", s)
	}
	if s["reserve_l"].(float64) != 8 { // max(8, 0.2 × 40)
		t.Fatalf("reserve = %v", s["reserve_l"])
	}
}

func TestPlanFuelBudgetInfeasible(t *testing.T) {
	r := request(t)
	r.FuelBudget.UsableAtDepartureL = 9
	if _, e := compute(r, grid(5), nil, environment.Environment{}); e == nil || e.Code != "FUEL_BUDGET_INFEASIBLE" {
		t.Fatalf("got %v", e)
	}
}

func TestPlanDeadline(t *testing.T) {
	r := request(t)
	r.LatestReturnAt = r.DepartAt.Add(3600e9) // spot alone takes an hour
	if _, e := compute(r, grid(5), nil, environment.Environment{}); e == nil || e.Code != "DEADLINE_INFEASIBLE" {
		t.Fatalf("got %v", e)
	}
}

func TestPlanSafetyLimit(t *testing.T) {
	r := request(t)
	lim := 1.0
	r.Safety.MaxWaveHeightM = &lim
	if _, e := compute(r, grid(5), nil, environment.Environment{MaxWaveHeightM: 1.5}); e == nil || e.Code != "SAFETY_LIMIT_EXCEEDED" {
		t.Fatalf("got %v", e)
	}
}

func TestPlanSpotInClosedZone(t *testing.T) {
	r := request(t)
	z := routing.NewPolygon([][]routing.Point{{{Lon: 0.017, Lat: -1}, {Lon: 0.019, Lat: -1}, {Lon: 0.019, Lat: 1}, {Lon: 0.017, Lat: 1}, {Lon: 0.017, Lat: -1}}})
	if _, e := compute(r, grid(5), []routing.Polygon{z}, environment.Environment{}); e == nil || e.Code != "POINT_IN_CLOSED_ZONE" {
		t.Fatalf("got %v", e)
	}
}

func TestValidateRejects(t *testing.T) {
	r := request(t)
	r.Outbound.STW = 5
	if e := r.Validate(); e == nil || e.Code != "INVALID_STW_RANGE" {
		t.Fatalf("got %v", e)
	}
	r = request(t)
	r.SpotActivity.PositionMode = "drift"
	if e := r.Validate(); e == nil || e.Code != "MODE_NOT_AVAILABLE" {
		t.Fatalf("got %v", e)
	}
	r = request(t)
	r.CalculationMode = "time_dependent"
	if e := r.Validate(); e == nil || e.Code != "MODE_NOT_AVAILABLE" {
		t.Fatalf("got %v", e)
	}
}
