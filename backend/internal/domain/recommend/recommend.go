// Package recommend ranks candidate cells and predicts fuel and catch for the four recommendation
// types (docs/AGENTS.md 10.4, 11.2 cold start). Pure rules: candidates arrive already filtered
// (in range, outside closed zones) by the database.
package recommend

import "math"

type Zone struct {
	ID     *string `json:"id"`
	Name   *string `json:"name"`
	Status string  `json:"status"` // normal | restricted | rehab
	Closed bool    `json:"closed"` // rehab, or restricted with the quota used up, at departure
}

type Cell struct {
	GridID         string   `json:"grid_id"`
	Lat            float64  `json:"lat"`
	Lng            float64  `json:"lng"`
	DistM          float64  `json:"dist_m"`
	PotentialScore *float64 `json:"potential_score"`
	Zone           Zone     `json:"zone"`
}

type Input struct {
	Candidates    []Cell
	Habitual      *Cell    // most visited cell; may be closed now
	FuelPerKm     float64  // user's history, or the configured default
	AvgCatchKg    *float64 // nil before any trip
	BaselineFuelL *float64
	WeatherFactor float64 // see WeatherFactor
}

type Item struct {
	Type                string   `json:"type"`
	GridID              string   `json:"grid_id"`
	PredictedFuelLiters float64  `json:"predicted_fuel_liters"`
	FuelEfficiencyPct   *float64 `json:"fuel_efficiency_pct"`
	PredictedCatchKg    *float64 `json:"predicted_catch_kg"`
	PredictedCatchMin   *float64 `json:"predicted_catch_min"`
	PredictedCatchMax   *float64 `json:"predicted_catch_max"`
	Confidence          float64  `json:"confidence"`
	Reason              string   `json:"reason"`
}

type Unavailable struct {
	Type       string `json:"type"`
	ReasonCode string `json:"reason_code"`
}

// Heuristic output is low confidence by definition.
const confidence = 0.3

var weighted = []struct {
	typ           string
	wFuel, wCatch float64
	reason        string
}{
	{"fuel_saving", 0.6, 0.2, "Paling dekat dari dermaga dengan potensi ikan cukup"},
	{"catch_max", 0.2, 0.6, "Potensi ikan tertinggi dalam jangkauan"},
	{"balanced", 0.4, 0.4, "Seimbang antara jarak tempuh dan potensi ikan"},
}

// WeatherFactor scales fuel for headwind and waves. Missing values add nothing.
// shortcut: uncalibrated coefficients; replace with the ML fuel model (AGENTS.md 11.2).
func WeatherFactor(windMs, waveM *float64) float64 {
	f := 1.0
	if windMs != nil {
		f += 0.03 * math.Max(0, *windMs-4)
	}
	if waveM != nil {
		f += 0.1 * *waveM
	}
	return math.Min(f, 1.5)
}

// Rank returns one item per type in AGENTS.md order, and the types without a valid candidate.
func Rank(in Input) ([]Item, []Unavailable) {
	items := []Item{}
	unavailable := []Unavailable{}
	norm := normaliser(in.Candidates)

	for _, w := range weighted {
		best, bestScore := -1, math.Inf(-1)
		for i, c := range in.Candidates {
			fuelN, catchN := norm(c)
			s := w.wFuel*fuelN + w.wCatch*orHalf(catchN)
			if s > bestScore || (s == bestScore && c.DistM < in.Candidates[best].DistM) {
				best, bestScore = i, s
			}
		}
		if best < 0 {
			unavailable = append(unavailable, Unavailable{w.typ, "NO_VALID_CANDIDATE"})
			continue
		}
		_, catchN := norm(in.Candidates[best])
		items = append(items, in.item(w.typ, in.Candidates[best], catchN, w.reason))
	}

	switch h := in.Habitual; {
	case h != nil && !h.Zone.Closed:
		_, catchN := norm(*h)
		items = append(items, in.item("habitual", *h, catchN, "Area yang paling sering Anda datangi"))
	case h != nil && len(in.Candidates) > 0:
		near := in.Candidates[0]
		for _, c := range in.Candidates[1:] {
			if haversineM(h.Lat, h.Lng, c.Lat, c.Lng) < haversineM(h.Lat, h.Lng, near.Lat, near.Lng) {
				near = c
			}
		}
		_, catchN := norm(near)
		items = append(items, in.item("habitual", near, catchN,
			"Area yang biasa Anda datangi sedang ditutup; diganti area terdekat yang diizinkan"))
	default:
		unavailable = append(unavailable, Unavailable{"habitual", "NO_VALID_CANDIDATE"})
	}
	return items, unavailable
}

// normaliser maps a cell to F = 1 - dist/maxDist and C = min-max scaled potential (nil when unknown).
func normaliser(cells []Cell) func(Cell) (float64, *float64) {
	maxDist, lo, hi := 0.0, math.Inf(1), math.Inf(-1)
	for _, c := range cells {
		maxDist = math.Max(maxDist, c.DistM)
		if c.PotentialScore != nil {
			lo, hi = math.Min(lo, *c.PotentialScore), math.Max(hi, *c.PotentialScore)
		}
	}
	return func(c Cell) (float64, *float64) {
		fuelN := 1.0
		if maxDist > 0 {
			fuelN = math.Max(0, 1-c.DistM/maxDist)
		}
		if c.PotentialScore == nil || hi < lo {
			return fuelN, nil
		}
		catchN := 1.0
		if hi > lo {
			catchN = math.Min(1, math.Max(0, (*c.PotentialScore-lo)/(hi-lo)))
		}
		return fuelN, &catchN
	}
}

func orHalf(v *float64) float64 {
	if v == nil {
		return 0.5
	}
	return *v
}

func (in Input) item(typ string, c Cell, catchN *float64, reason string) Item {
	fuel := round1(2 * c.DistM / 1000 * in.FuelPerKm * in.WeatherFactor)
	it := Item{Type: typ, GridID: c.GridID, PredictedFuelLiters: fuel, Confidence: confidence, Reason: reason}
	if b := in.BaselineFuelL; b != nil && *b > 0 {
		it.FuelEfficiencyPct = ptr(round1((*b - fuel) / *b * 100))
	}
	if a := in.AvgCatchKg; a != nil {
		kg := *a * (0.5 + orHalf(catchN))
		it.PredictedCatchKg, it.PredictedCatchMin, it.PredictedCatchMax = ptr(round1(kg)), ptr(round1(kg*0.7)), ptr(round1(kg*1.3))
	}
	return it
}

func haversineM(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371000.0
	rad := math.Pi / 180
	dLat, dLng := (lat2-lat1)*rad, (lng2-lng1)*rad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * r * math.Asin(math.Sqrt(a))
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }
func ptr(v float64) *float64   { return &v }
