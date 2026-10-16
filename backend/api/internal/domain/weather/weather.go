// Package weather holds the point-forecast rules for fishers (docs/AGENTS.md 12.B.8, 15).
// Missing values stay nil and never count as calm conditions.
package weather

import (
	"math"
	"strings"
	"time"
)

// Hour is one forecast hour. Risk and labels are filled by Enrich.
type Hour struct {
	Time         string   `json:"time"`
	WeatherCode  *int     `json:"weather_code"`
	WeatherLabel *string  `json:"weather_label,omitempty"`
	TempC        *float64 `json:"temp_c"`
	WindSpeedMs  *float64 `json:"wind_speed_ms"`
	WindDirDeg   *float64 `json:"wind_dir_deg"`
	WindDirLabel *string  `json:"wind_dir_label"`
	WaveHeightM  *float64 `json:"wave_height_m"`
	Risk         string   `json:"risk"`
}

type Location struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type Warning struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Reason string `json:"reason"`
}

type Report struct {
	Location  Location  `json:"location"`
	FetchedAt string    `json:"fetched_at"`
	Current   Hour      `json:"current"`
	Hourly    []Hour    `json:"hourly"`
	Warnings  []Warning `json:"warnings"`
}

// AreaPoint is one lattice sample for wind arrows on the map (AGENTS.md 12.A.4 getWeatherArea).
type AreaPoint struct {
	CellKey string  `json:"cell_key"`
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	Hour
}

type Area struct {
	ForecastTime string      `json:"forecast_time"`
	Points       []AreaPoint `json:"points"`
}

// Thresholds from AGENTS.md 15.
const (
	highWindMs   = 10
	highWaveM    = 2
	mediumWindMs = 7
	mediumWaveM  = 1.25
)

// Risk is high when any known value is over the high threshold. Otherwise a missing value makes it
// "unknown", because a calm reading cannot be claimed without data.
func Risk(windMs, waveM *float64) string {
	if over(windMs, highWindMs) || over(waveM, highWaveM) {
		return "high"
	}
	if windMs == nil || waveM == nil {
		return "unknown"
	}
	if *windMs > mediumWindMs || *waveM > mediumWaveM {
		return "medium"
	}
	return "low"
}

func over(v *float64, limit float64) bool { return v != nil && *v > limit }

var dirLabels = [8]string{"U", "TL", "T", "TG", "S", "BD", "B", "BL"}

// DirLabel names the 45° sector of a wind "from" direction in Indonesian (U = north).
func DirLabel(deg float64) string {
	i := int(math.Round(math.Mod(math.Mod(deg, 360)+360, 360)/45)) % 8
	return dirLabels[i]
}

// Label translates a WMO weather code to Indonesian.
func Label(code int) string {
	switch {
	case code == 0:
		return "Cerah"
	case code <= 2:
		return "Berawan sebagian"
	case code == 3:
		return "Berawan"
	case code == 45 || code == 48:
		return "Berkabut"
	case code >= 51 && code <= 57:
		return "Gerimis"
	case code >= 61 && code <= 67, code >= 80 && code <= 82:
		return "Hujan"
	case code >= 95:
		return "Badai petir"
	}
	return "Lainnya"
}

func reasons(h Hour) []string {
	var r []string
	if over(h.WindSpeedMs, highWindMs) {
		r = append(r, "Angin > 10 m/s")
	}
	if over(h.WaveHeightM, highWaveM) {
		r = append(r, "Gelombang > 2 m")
	}
	return r
}

// Enrich fills labels and risk on every hour, then merges consecutive high-risk hours into warnings.
func Enrich(hours []Hour) []Warning {
	warnings := []Warning{}
	var run *Warning
	for i := range hours {
		h := &hours[i]
		h.Risk = Risk(h.WindSpeedMs, h.WaveHeightM)
		if h.WindDirDeg != nil {
			l := DirLabel(*h.WindDirDeg)
			h.WindDirLabel = &l
		}
		if h.Risk != "high" {
			run = nil
			continue
		}
		end := h.Time
		if t, err := time.Parse(time.RFC3339, h.Time); err == nil {
			end = t.Add(time.Hour).Format(time.RFC3339)
		}
		if run == nil {
			warnings = append(warnings, Warning{From: h.Time})
			run = &warnings[len(warnings)-1]
		}
		run.To = end
		for _, r := range reasons(*h) {
			if !strings.Contains(run.Reason, r) {
				run.Reason = strings.TrimPrefix(run.Reason+", "+r, ", ")
			}
		}
	}
	return warnings
}
