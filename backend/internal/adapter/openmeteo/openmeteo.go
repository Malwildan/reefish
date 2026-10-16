// Package openmeteo samples wind, current and waves at one point (spec 13.3).
// The result is used as a spatially uniform static snapshot for the whole trip.
package openmeteo

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"time"

	"nelayan-route/internal/domain/environment"
)

const (
	forecastURL = "https://api.open-meteo.com/v1/forecast"
	marineURL   = "https://marine-api.open-meteo.com/v1/marine"
	hourLayout  = "2006-01-02T15:04"
)

// Provider implements planroute.EnvironmentProvider.
type Provider struct{ HTTP *http.Client }

type response struct {
	Latitude    float64                    `json:"latitude"`
	Longitude   float64                    `json:"longitude"`
	HourlyUnits map[string]string          `json:"hourly_units"`
	Hourly      map[string]json.RawMessage `json:"hourly"`
}

type series struct {
	times  []time.Time
	values map[string][]*float64
}

var wantUnits = map[string]string{
	"wind_speed_10m": "m/s", "wind_direction_10m": "°", "wind_gusts_10m": "m/s",
	"ocean_current_velocity": "m/s", "ocean_current_direction": "°", "wave_height": "m",
	"temperature_2m": "°C", "weather_code": "wmo code",
}

func parse(body []byte, vars ...string) (series, response, error) {
	var r response
	if err := json.Unmarshal(body, &r); err != nil {
		return series{}, r, err
	}
	var raw []string
	if err := json.Unmarshal(r.Hourly["time"], &raw); err != nil {
		return series{}, r, fmt.Errorf("hourly.time: %w", err)
	}
	s := series{values: map[string][]*float64{}}
	for _, t := range raw {
		tt, err := time.Parse(hourLayout, t)
		if err != nil {
			return series{}, r, err
		}
		s.times = append(s.times, tt)
	}
	for _, v := range vars {
		if u := r.HourlyUnits[v]; u != wantUnits[v] {
			return series{}, r, fmt.Errorf("%s unit %q, want %q", v, u, wantUnits[v])
		}
		var vals []*float64
		if err := json.Unmarshal(r.Hourly[v], &vals); err != nil || len(vals) != len(s.times) {
			return series{}, r, fmt.Errorf("hourly.%s missing or misaligned", v)
		}
		s.values[v] = vals
	}
	return s, r, nil
}

// at returns the value at the hour nearest t (within 30 min); null stays an error, never zero.
func (s series) at(v string, t time.Time) (float64, error) {
	for i, ts := range s.times {
		if d := ts.Sub(t); d > -30*time.Minute && d <= 30*time.Minute {
			if s.values[v][i] == nil {
				return 0, fmt.Errorf("%w: %s null at %s", environment.ErrCoverage, v, ts.Format(hourLayout))
			}
			return *s.values[v][i], nil
		}
	}
	return 0, fmt.Errorf("%w: %s has no sample near %s", environment.ErrCoverage, v, t.Format(time.RFC3339))
}

// max returns the largest value over every hour touching [from, to]; any null in the window fails.
func (s series) max(v string, from, to time.Time) (float64, error) {
	m, found := math.Inf(-1), false
	for i, ts := range s.times {
		if ts.Before(from.Truncate(time.Hour)) || ts.After(to) {
			continue
		}
		if s.values[v][i] == nil {
			return 0, fmt.Errorf("%w: %s null at %s", environment.ErrCoverage, v, ts.Format(hourLayout))
		}
		m, found = math.Max(m, *s.values[v][i]), true
	}
	if !found || s.times[len(s.times)-1].Before(to.Truncate(time.Hour)) {
		return 0, fmt.Errorf("%w: %s does not cover the trip window", environment.ErrCoverage, v)
	}
	return m, nil
}

func get(ctx context.Context, c *http.Client, base string, q url.Values) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	res, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("open-meteo %s: HTTP %d", base, res.StatusCode)
	}
	return body, nil
}

// Fetch samples both APIs at (lat, lon): cost uses the hour of depart, safety uses the whole window.
func (p Provider) Fetch(ctx context.Context, lat, lon float64, depart, latestReturn time.Time) (environment.Environment, error) {
	q := url.Values{
		"latitude":        {fmt.Sprint(lat)},
		"longitude":       {fmt.Sprint(lon)},
		"wind_speed_unit": {"ms"},
		"timezone":        {"GMT"},
		"start_date":      {depart.UTC().Format("2006-01-02")},
		"end_date":        {latestReturn.UTC().Format("2006-01-02")},
	}
	fq := cloneWith(q, "hourly", "wind_speed_10m,wind_direction_10m,wind_gusts_10m")
	mq := cloneWith(q, "hourly", "ocean_current_velocity,ocean_current_direction,wave_height")
	mq.Set("cell_selection", "sea")

	fb, err := get(ctx, p.HTTP, forecastURL, fq)
	if err != nil {
		return environment.Environment{}, err
	}
	mb, err := get(ctx, p.HTTP, marineURL, mq)
	if err != nil {
		return environment.Environment{}, err
	}
	return build(fb, mb, depart, latestReturn)
}

func build(forecast, marine []byte, depart, latestReturn time.Time) (environment.Environment, error) {
	fs, _, err := parse(forecast, "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m")
	if err != nil {
		return environment.Environment{}, err
	}
	ms, mr, err := parse(marine, "ocean_current_velocity", "ocean_current_direction", "wave_height")
	if err != nil {
		return environment.Environment{}, err
	}
	e := environment.Environment{
		ReferenceAt: depart.UTC().Format(time.RFC3339), Provider: "open-meteo",
		SampledLat: mr.Latitude, SampledLon: mr.Longitude, FetchedAt: time.Now().UTC().Format(time.RFC3339),
	}
	for _, f := range []struct {
		dst *float64
		s   series
		v   string
	}{
		{&e.WindSpeedMps, fs, "wind_speed_10m"}, {&e.WindFromDeg, fs, "wind_direction_10m"},
		{&e.CurrentSpeedMps, ms, "ocean_current_velocity"}, {&e.CurrentToDeg, ms, "ocean_current_direction"},
	} {
		if *f.dst, err = f.s.at(f.v, depart); err != nil {
			return environment.Environment{}, err
		}
	}
	if e.MaxGustMps, err = fs.max("wind_gusts_10m", depart, latestReturn); err != nil {
		return environment.Environment{}, err
	}
	if e.MaxWaveHeightM, err = ms.max("wave_height", depart, latestReturn); err != nil {
		return environment.Environment{}, err
	}
	return e, nil
}

func cloneWith(q url.Values, k, v string) url.Values {
	c := url.Values{}
	for kk, vv := range q {
		c[kk] = vv
	}
	c.Set(k, v)
	return c
}
