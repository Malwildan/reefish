package openmeteo

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"

	"nelayan-route/internal/domain/weather"
)

// Area samples every point at one hour with two multi-location requests (forecast + marine).
// Open-Meteo answers a list of coordinates with a JSON array in the same order.
func (p Provider) Area(ctx context.Context, pts []weather.Location, at time.Time) ([]weather.Hour, error) {
	at = at.UTC().Truncate(time.Hour)
	lats, lngs := make([]string, len(pts)), make([]string, len(pts))
	for i, pt := range pts {
		lats[i], lngs[i] = fmt.Sprint(pt.Lat), fmt.Sprint(pt.Lng)
	}
	q := url.Values{
		"latitude":        {strings.Join(lats, ",")},
		"longitude":       {strings.Join(lngs, ",")},
		"wind_speed_unit": {"ms"},
		"timezone":        {"GMT"},
		"start_hour":      {at.Format(hourLayout)},
		"end_hour":        {at.Format(hourLayout)},
	}
	fb, err := get(ctx, p.HTTP, forecastURL, cloneWith(q, "hourly", "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"))
	if err != nil {
		return nil, err
	}
	mq := cloneWith(q, "hourly", "wave_height")
	mq.Set("cell_selection", "sea")
	mb, marineErr := get(ctx, p.HTTP, marineURL, mq)
	return buildArea(fb, mb, marineErr, len(pts))
}

func buildArea(forecast, marine []byte, marineErr error, n int) ([]weather.Hour, error) {
	var fs, ms []json.RawMessage
	if err := json.Unmarshal(forecast, &fs); err != nil || len(fs) != n {
		return nil, fmt.Errorf("forecast: want %d locations, got %d (%v)", n, len(fs), err)
	}
	if marineErr == nil && (json.Unmarshal(marine, &ms) != nil || len(ms) != n) {
		ms = nil // waves stay nil rather than misaligned
	}
	out := make([]weather.Hour, n)
	for i := range fs {
		var mb []byte
		var merr error = marineErr
		if ms != nil {
			mb = ms[i]
		} else if merr == nil {
			merr = fmt.Errorf("marine unavailable")
		}
		_, hs, err := buildPoint(fs[i], mb, merr)
		if err != nil {
			return nil, fmt.Errorf("location %d: %w", i, err)
		}
		if len(hs) == 0 {
			return nil, fmt.Errorf("location %d: no hourly data", i)
		}
		out[i] = hs[0]
	}
	return out, nil
}
