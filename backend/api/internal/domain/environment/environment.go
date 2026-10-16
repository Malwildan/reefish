// Package environment holds the normalised marine conditions used by route planning.
package environment

import "errors"

// ErrCoverage means required data is missing or outside the provider's horizon; never treat it as calm sea.
var ErrCoverage = errors.New("ENVIRONMENT_COVERAGE_GAP")

// Environment is a spatially uniform static snapshot. Contract: wind "from", current "to", m/s (spec 2).
type Environment struct {
	WindSpeedMps    float64 `json:"wind_speed_mps"`
	WindFromDeg     float64 `json:"wind_from_deg"`
	CurrentSpeedMps float64 `json:"current_speed_mps"`
	CurrentToDeg    float64 `json:"current_to_deg"`
	// Worst values over the trip window, for safety checks (spec 3).
	MaxGustMps     float64 `json:"max_wind_gust_mps"`
	MaxWaveHeightM float64 `json:"max_significant_wave_height_m"`
	ReferenceAt    string  `json:"static_reference_at"`
	Provider       string  `json:"provider"`
	SampledLat     float64 `json:"sampled_lat"`
	SampledLon     float64 `json:"sampled_lon"`
	FetchedAt      string  `json:"fetched_at"`
}
