package openmeteo

import (
	"errors"
	"testing"
)

const pointForecast = `{"latitude":-8.4,"longitude":112.6,
"hourly_units":{"time":"iso8601","temperature_2m":"°C","weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"°"},
"hourly":{"time":["2026-10-16T05:00","2026-10-16T06:00"],
"temperature_2m":[28.1,null],"weather_code":[2,3],"wind_speed_10m":[4.2,11],"wind_direction_10m":[120,125]}}`

const pointMarine = `{"latitude":-8.42,"longitude":112.6,
"hourly_units":{"time":"iso8601","wave_height":"m"},
"hourly":{"time":["2026-10-16T05:00","2026-10-16T06:00"],"wave_height":[0.8,null]}}`

func TestBuildPoint(t *testing.T) {
	loc, hs, err := buildPoint([]byte(pointForecast), []byte(pointMarine), nil)
	if err != nil {
		t.Fatal(err)
	}
	if loc.Lat != -8.4 || len(hs) != 2 || hs[0].Time != "2026-10-16T05:00:00Z" {
		t.Fatalf("loc %+v hours %+v", loc, hs)
	}
	if *hs[0].WaveHeightM != 0.8 || *hs[0].WeatherCode != 2 || *hs[0].TempC != 28.1 {
		t.Errorf("hour 0 = %+v", hs[0])
	}
	if hs[1].WaveHeightM != nil || hs[1].TempC != nil {
		t.Errorf("null must stay nil: %+v", hs[1])
	}
}

func TestBuildPointWithoutMarine(t *testing.T) {
	_, hs, err := buildPoint([]byte(pointForecast), nil, errors.New("HTTP 400"))
	if err != nil || hs[0].WaveHeightM != nil {
		t.Fatalf("marine failure must leave waves nil: %v %+v", err, hs)
	}
}

func TestBuildPointRejectsWrongUnit(t *testing.T) {
	bad := []byte(`{"hourly_units":{"temperature_2m":"°F","weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"°"},
"hourly":{"time":["2026-10-16T05:00"],"temperature_2m":[80],"weather_code":[1],"wind_speed_10m":[1],"wind_direction_10m":[1]}}`)
	if _, _, err := buildPoint(bad, nil, errors.New("skip")); err == nil {
		t.Fatal("expected unit error")
	}
}
