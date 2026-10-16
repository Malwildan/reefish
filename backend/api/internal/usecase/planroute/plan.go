package planroute

import (
	"errors"
	"math"
	"time"

	"nelayan-route/internal/domain/environment"
	"nelayan-route/internal/domain/physics"
	"nelayan-route/internal/domain/routing"
)

type LegResult struct {
	Phase       string  `json:"phase"`
	DepartureAt string  `json:"departure_at"`
	ArrivalAt   string  `json:"arrival_at"`
	DistanceM   float64 `json:"distance_m"`
	DurationS   float64 `json:"duration_s"`
	FuelL       float64 `json:"estimated_fuel_l"`
	Geometry    any     `json:"geometry"`
}

type Result struct {
	Status          string                  `json:"status"`
	PlanningMode    string                  `json:"planning_mode"`
	Eligibility     string                  `json:"eligibility"`
	CalculationMode string                  `json:"calculation_mode"`
	Objective       string                  `json:"objective"`
	Search          map[string]string       `json:"search"`
	Summary         map[string]any          `json:"summary"`
	Legs            []LegResult             `json:"legs"`
	Environment     environment.Environment `json:"environment"`
	Comparison      map[string]any          `json:"comparison"`
	Quality         map[string]any          `json:"quality"`
	Assumptions     []string                `json:"assumptions"`
}

func lineString(path []routing.Point) map[string]any {
	coords := make([][2]float64, len(path))
	for i, p := range path {
		coords[i] = [2]float64{p.Lon, p.Lat}
	}
	return map[string]any{"type": "LineString", "coordinates": coords}
}

func ts(t time.Time) string { return t.UTC().Format(time.RFC3339) }

func secs(s float64) time.Duration { return time.Duration(math.Round(s * float64(time.Second))) }

// compute builds the round trip from already-loaded data. Legs are searched independently: valid here because the
// environment is static, the spot and its duration are fixed, and fuel rate is constant per leg,
// so each leg's fuel-minimal path is also its fastest and the deadline check below is exact (spec 10.1).
func compute(r *Request, grid *routing.Grid, closed []routing.Polygon, env environment.Environment) (*Result, *Error) {
	curves := map[string]physics.FuelCurve{}
	for _, c := range r.Vessel.FuelCurves {
		fc, err := physics.NewFuelCurve(c.Points)
		if err != nil {
			return nil, invalid("INVALID_FUEL_MODEL", "%s: %v", c.LoadClass, err)
		}
		curves[c.LoadClass] = fc
	}
	rate := func(name string, ph Phase) (float64, *Error) {
		c, ok := curves[ph.LoadClass]
		if !ok {
			return 0, invalid("INVALID_FUEL_MODEL", "%s.load_class %q has no fuel curve", name, ph.LoadClass)
		}
		q, err := c.Rate(ph.STW)
		if err != nil {
			return 0, invalid("INVALID_STW_RANGE", "%s: %v", name, err)
		}
		return q, nil
	}
	qOut, e := rate("outbound", r.Outbound)
	if e != nil {
		return nil, e
	}
	qIn, e := rate("inbound", r.Inbound)
	if e != nil {
		return nil, e
	}

	warnings := []string{"STATIC_ENVIRONMENT_FOR_ENTIRE_TRIP", "UNIFORM_FIELD_ASSUMPTION", "FUEL_MODEL_UNCALIBRATED", "WIND_WAVE_FUEL_CORRECTION_UNAVAILABLE", "CONNECTOR_LAND_NOT_CHECKED"}
	sf := r.Safety
	if sf.MaxWindGustMps != nil && env.MaxGustMps > *sf.MaxWindGustMps {
		return nil, invalid("SAFETY_LIMIT_EXCEEDED", "forecast gust %.1f m/s exceeds policy %.1f m/s", env.MaxGustMps, *sf.MaxWindGustMps)
	}
	if sf.MaxWaveHeightM != nil && env.MaxWaveHeightM > *sf.MaxWaveHeightM {
		return nil, invalid("SAFETY_LIMIT_EXCEEDED", "forecast Hs %.2f m exceeds policy %.2f m", env.MaxWaveHeightM, *sf.MaxWaveHeightM)
	}
	if sf.MaxWindGustMps == nil || sf.MaxWaveHeightM == nil {
		warnings = append(warnings, "WEATHER_SAFETY_NOT_ASSESSED")
	}

	for name, p := range map[string]*Pos{"origin": r.Origin, "destination": r.Destination, "return_to": r.ReturnTo} {
		for _, z := range closed {
			if z.Contains(p.point()) {
				return nil, invalid("POINT_IN_CLOSED_ZONE", "%s lies inside a closed conservation zone", name)
			}
		}
	}

	current := physics.VectorTo(env.CurrentSpeedMps, env.CurrentToDeg)
	leg := func(name string, from, to *Pos, stw, q float64) (routing.Leg, *Error) {
		l, err := grid.Route(from.point(), to.point(), routing.LegParams{
			STW: stw, RateLPH: q, Current: current, MinProgress: sf.MinProgressMps, Obstacles: closed,
		})
		switch {
		case errors.Is(err, routing.ErrNoConnector):
			return l, invalid("INVALID_COORDINATES", "%s: no sea cell within %.0f m of an endpoint (outside the 500 m grid)", name, routing.ConnectorMaxM)
		case errors.Is(err, routing.ErrNoRoute):
			e := invalid("NO_ROUTE_IN_SEARCH_GRAPH", "%s: no traversable path in the 500 m grid with current zones and current conditions", name)
			e.Details = map[string]any{"scope": "bounded_grid_500m", "grid_cells": grid.Len(), "closed_zones": len(closed)}
			return l, e
		}
		return l, nil
	}
	out, e := leg("outbound", r.Origin, r.Destination, r.Outbound.STW, qOut)
	if e != nil {
		return nil, e
	}
	in, e := leg("inbound", r.Destination, r.ReturnTo, r.Inbound.STW, qIn)
	if e != nil {
		return nil, e
	}

	spot := r.SpotActivity
	fSpot := spot.FuelRateLPH * spot.DurationS / 3600
	fTotal := out.FuelL + fSpot + in.FuelL
	b := r.FuelBudget
	reserve := physics.Reserve(b.ReserveFixedL, b.ReserveFraction, b.UsableAtDepartureL)
	arriveSpot := r.DepartAt.Add(secs(out.DurationS))
	leaveSpot := arriveSpot.Add(secs(spot.DurationS))
	returnAt := leaveSpot.Add(secs(in.DurationS))

	summary := map[string]any{
		"distance_m":                   out.DistanceM + in.DistanceM,
		"transit_duration_s":           out.DurationS + in.DurationS,
		"spot_duration_s":              spot.DurationS,
		"total_duration_s":             out.DurationS + spot.DurationS + in.DurationS,
		"estimated_fuel_outbound_l":    out.FuelL,
		"estimated_fuel_spot_l":        fSpot,
		"estimated_fuel_inbound_l":     in.FuelL,
		"estimated_fuel_other_l":       0.0,
		"estimated_fuel_total_l":       fTotal,
		"planning_fuel_l":              fTotal,
		"reserve_l":                    reserve,
		"fuel_required_with_reserve_l": fTotal + reserve,
		"usable_fuel_at_departure_l":   b.UsableAtDepartureL,
		"nominal_budget_pass":          fTotal+reserve <= b.UsableAtDepartureL,
		"return_at":                    ts(returnAt),
	}
	if fTotal+reserve > b.UsableAtDepartureL {
		e := invalid("FUEL_BUDGET_INFEASIBLE", "estimated fuel plus reserve exceeds usable fuel at departure")
		e.Details = summary
		return nil, e
	}
	if returnAt.After(r.LatestReturnAt) {
		e := invalid("DEADLINE_INFEASIBLE", "estimated return %s is after latest_return_at", ts(returnAt))
		e.Details = summary
		return nil, e
	}

	return &Result{
		Status:          "succeeded",
		PlanningMode:    "simulation",
		Eligibility:     "simulation_only",
		CalculationMode: "static_snapshot",
		Objective:       "fuel",
		Search: map[string]string{
			"algorithm": "dijkstra", "heuristic": "zero", "state_model": "cell_per_leg",
			"optimality": "optimal_in_discrete_model", "scope": "bounded_grid_500m",
		},
		Summary: summary,
		Legs: []LegResult{
			{"outbound", ts(r.DepartAt), ts(arriveSpot), out.DistanceM, out.DurationS, out.FuelL, lineString(out.Path)},
			{"inbound", ts(leaveSpot), ts(returnAt), in.DistanceM, in.DurationS, in.FuelL, lineString(in.Path)},
		},
		Environment: env,
		Comparison: map[string]any{
			"model_estimated_fuel_reduction_pct": nil,
			"measured_fuel_saving_pct":           nil,
			"reason":                             "UNCALIBRATED_MODEL_NO_VALID_COMPARISON",
		},
		Quality: map[string]any{
			"fuel_model_status":  "uncalibrated",
			"environment_source": "open-meteo",
			"safety_assessment":  "simulation_constraints_only",
			"uncertainty":        map[string]any{"method": "not_quantified", "scenario_range_l": nil},
			"warnings":           warnings,
		},
		Assumptions: []string{
			"STW dipertahankan selama transit",
			"Pengaruh leeway tidak dimodelkan",
			"Angin dan arus diambil di titik spot pada jam keberangkatan dan dianggap seragam",
			"Sel grid yang tidak ada dianggap daratan atau tanpa data",
			"Batas keselamatan simulasi bukan persetujuan operasi",
		},
	}, nil
}
