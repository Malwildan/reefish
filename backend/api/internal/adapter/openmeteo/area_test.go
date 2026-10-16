package openmeteo

import (
	"errors"
	"testing"
)

const areaForecast = `[` +
	`{"latitude":-8.4,"longitude":112.6,"hourly_units":{"time":"iso8601","temperature_2m":"°C","weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"°"},"hourly":{"time":["2026-10-16T05:00"],"temperature_2m":[28.1],"weather_code":[2],"wind_speed_10m":[4.2],"wind_direction_10m":[120]}},` +
	`{"latitude":-8.6,"longitude":112.8,"hourly_units":{"time":"iso8601","temperature_2m":"°C","weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"°"},"hourly":{"time":["2026-10-16T05:00"],"temperature_2m":[27.5],"weather_code":[3],"wind_speed_10m":[11],"wind_direction_10m":[90]}}]`

const areaMarine = `[` +
	`{"hourly_units":{"time":"iso8601","wave_height":"m"},"hourly":{"time":["2026-10-16T05:00"],"wave_height":[0.8]}},` +
	`{"hourly_units":{"time":"iso8601","wave_height":"m"},"hourly":{"time":["2026-10-16T05:00"],"wave_height":[null]}}]`

func TestBuildArea(t *testing.T) {
	hs, err := buildArea([]byte(areaForecast), []byte(areaMarine), nil, 2)
	if err != nil {
		t.Fatal(err)
	}
	if *hs[0].WaveHeightM != 0.8 || *hs[1].WindSpeedMs != 11 || hs[1].WaveHeightM != nil {
		t.Fatalf("hours %+v", hs)
	}
}

func TestBuildAreaMarineDown(t *testing.T) {
	hs, err := buildArea([]byte(areaForecast), nil, errors.New("HTTP 400"), 2)
	if err != nil || hs[0].WaveHeightM != nil || hs[0].TempC == nil {
		t.Fatalf("%v %+v", err, hs)
	}
}

func TestBuildAreaCountMismatch(t *testing.T) {
	if _, err := buildArea([]byte(areaForecast), nil, errors.New("x"), 3); err == nil {
		t.Fatal("expected error")
	}
}
