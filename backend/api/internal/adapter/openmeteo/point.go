package openmeteo

import (
	"context"
	"fmt"
	"math"
	"net/url"
	"time"

	"nelayan-route/internal/domain/weather"
)

// Point implements nelayan.Forecaster: hourly weather plus wave height for [from, from+hours).
// Waves stay nil when the marine API has no sea cell nearby or fails; nil is never read as calm.
func (p Provider) Point(ctx context.Context, lat, lng float64, from time.Time, hours int) (weather.Location, []weather.Hour, error) {
	from = from.UTC().Truncate(time.Hour)
	q := url.Values{
		"latitude":        {fmt.Sprint(lat)},
		"longitude":       {fmt.Sprint(lng)},
		"wind_speed_unit": {"ms"},
		"timezone":        {"GMT"},
		"start_hour":      {from.Format(hourLayout)},
		"end_hour":        {from.Add(time.Duration(hours-1) * time.Hour).Format(hourLayout)},
	}
	fb, err := get(ctx, p.HTTP, forecastURL, cloneWith(q, "hourly", "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"))
	if err != nil {
		return weather.Location{}, nil, err
	}
	mq := cloneWith(q, "hourly", "wave_height")
	mq.Set("cell_selection", "sea")
	mb, marineErr := get(ctx, p.HTTP, marineURL, mq)
	return buildPoint(fb, mb, marineErr)
}

func buildPoint(forecast, marine []byte, marineErr error) (weather.Location, []weather.Hour, error) {
	fs, fr, err := parse(forecast, "temperature_2m", "weather_code", "wind_speed_10m", "wind_direction_10m")
	if err != nil {
		return weather.Location{}, nil, err
	}
	waves := map[time.Time]*float64{}
	if marineErr == nil {
		if ms, _, err := parse(marine, "wave_height"); err == nil {
			for i, t := range ms.times {
				waves[t] = ms.values["wave_height"][i]
			}
		}
	}

	hours := make([]weather.Hour, len(fs.times))
	for i, t := range fs.times {
		h := weather.Hour{
			Time:        t.UTC().Format(time.RFC3339),
			TempC:       fs.values["temperature_2m"][i],
			WindSpeedMs: fs.values["wind_speed_10m"][i],
			WindDirDeg:  fs.values["wind_direction_10m"][i],
			WaveHeightM: waves[t],
		}
		if c := fs.values["weather_code"][i]; c != nil {
			code := int(math.Round(*c))
			h.WeatherCode = &code
		}
		hours[i] = h
	}
	return weather.Location{Lat: fr.Latitude, Lng: fr.Longitude}, hours, nil
}
