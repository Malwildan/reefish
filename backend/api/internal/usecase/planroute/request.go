package planroute

import (
	"time"

	"nelayan-route/internal/domain/physics"
	"nelayan-route/internal/domain/routing"
)

const (
	maxSpotDuration = 24 * time.Hour
	maxTripWindow   = 48 * time.Hour // Open-Meteo horizon kept short and reliable
)

type Pos struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

func (p *Pos) point() routing.Point { return routing.Point{Lon: p.Lon, Lat: p.Lat} }

type Phase struct {
	STW       float64 `json:"stw_mps"`
	LoadClass string  `json:"load_class"`
}

type Request struct {
	Origin          *Pos      `json:"origin"`
	Destination     *Pos      `json:"destination"`
	ReturnTo        *Pos      `json:"return_to"`
	DepartAt        time.Time `json:"depart_at"`
	LatestReturnAt  time.Time `json:"latest_return_at"`
	CalculationMode string    `json:"calculation_mode"`
	Vessel          struct {
		STWMin     float64 `json:"stw_min_mps"`
		STWMax     float64 `json:"stw_max_mps"`
		FuelCurves []struct {
			LoadClass string               `json:"load_class"`
			Points    []physics.CurvePoint `json:"points"`
		} `json:"fuel_curves"`
	} `json:"vessel"`
	SpotActivity struct {
		DurationS    float64 `json:"duration_s"`
		PositionMode string  `json:"position_mode"`
		FuelRateLPH  float64 `json:"fuel_rate_lph"`
	} `json:"spot_activity"`
	Outbound   Phase `json:"outbound"`
	Inbound    Phase `json:"inbound"`
	FuelBudget struct {
		UsableAtDepartureL float64 `json:"usable_at_departure_l"`
		ReserveFixedL      float64 `json:"reserve_fixed_l"`
		ReserveFraction    float64 `json:"reserve_fraction"`
	} `json:"fuel_budget"`
	// Thresholds come from the caller's vessel/area policy; there are no universal defaults (spec 9.2).
	Safety struct {
		MinProgressMps float64  `json:"min_progress_mps"`
		MaxWindGustMps *float64 `json:"max_wind_gust_mps"`
		MaxWaveHeightM *float64 `json:"max_significant_wave_height_m"`
	} `json:"safety"`
}

func validPos(name string, p *Pos) *Error {
	if p == nil {
		return invalid("INVALID_COORDINATES", "%s is required", name)
	}
	if p.Lat < -90 || p.Lat > 90 || p.Lon < -180 || p.Lon > 180 {
		return invalid("INVALID_COORDINATES", "%s out of range", name)
	}
	return nil
}

// Validate checks request semantics that need no external data (spec 12.9).
func (r *Request) Validate() *Error {
	for name, p := range map[string]*Pos{"origin": r.Origin, "destination": r.Destination, "return_to": r.ReturnTo} {
		if err := validPos(name, p); err != nil {
			return err
		}
	}
	if r.CalculationMode != "" && r.CalculationMode != "static_snapshot" {
		return invalid("MODE_NOT_AVAILABLE", "only static_snapshot is available")
	}
	if r.DepartAt.IsZero() || !r.LatestReturnAt.After(r.DepartAt) {
		return invalid("INVALID_TIME_WINDOW", "depart_at must be before latest_return_at")
	}
	if r.LatestReturnAt.Sub(r.DepartAt) > maxTripWindow {
		return invalid("FORECAST_HORIZON_INSUFFICIENT", "trip window longer than %s", maxTripWindow)
	}
	v := r.Vessel
	if !(v.STWMin > 0 && v.STWMax >= v.STWMin) {
		return invalid("INVALID_STW_RANGE", "vessel needs 0 < stw_min_mps <= stw_max_mps")
	}
	for name, ph := range map[string]Phase{"outbound": r.Outbound, "inbound": r.Inbound} {
		if ph.STW < v.STWMin || ph.STW > v.STWMax {
			return invalid("INVALID_STW_RANGE", "%s.stw_mps outside vessel range", name)
		}
	}
	s := r.SpotActivity
	if s.PositionMode != "station_keeping" {
		return invalid("MODE_NOT_AVAILABLE", "spot_activity.position_mode must be station_keeping; drift is not supported")
	}
	if s.DurationS < 0 || s.DurationS > maxSpotDuration.Seconds() || s.FuelRateLPH < 0 {
		return invalid("INVALID_SPOT_ACTIVITY", "duration_s must be within [0, %v] and fuel_rate_lph >= 0", maxSpotDuration.Seconds())
	}
	b := r.FuelBudget
	if !(b.UsableAtDepartureL > 0) || b.ReserveFixedL < 0 || b.ReserveFraction < 0 || b.ReserveFraction > 1 {
		return invalid("INVALID_FUEL_BUDGET", "usable_at_departure_l > 0, reserve_fixed_l >= 0, reserve_fraction in [0,1]")
	}
	if !(r.Safety.MinProgressMps > 0) {
		return invalid("INVALID_SAFETY_POLICY", "safety.min_progress_mps must be > 0")
	}
	return nil
}
