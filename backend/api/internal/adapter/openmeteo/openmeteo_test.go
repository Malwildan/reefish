package openmeteo

import (
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"nelayan-route/internal/domain/environment"
)

func fixtures(t *testing.T) ([]byte, []byte) {
	f, err := os.ReadFile("testdata/forecast.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := os.ReadFile("testdata/marine.json")
	if err != nil {
		t.Fatal(err)
	}
	return f, m
}

func TestBuildFromFixtures(t *testing.T) {
	f, m := fixtures(t)
	depart := time.Date(2026, 10, 15, 3, 0, 0, 0, time.UTC)
	e, err := build(f, m, depart, depart.Add(6*time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if e.CurrentSpeedMps != 0.66 { // fixture value at 03:00
		t.Errorf("current = %v, want 0.66", e.CurrentSpeedMps)
	}
	if e.MaxGustMps < e.WindSpeedMps || e.MaxWaveHeightM <= 0 {
		t.Errorf("implausible safety envelope: %+v", e)
	}
}

func TestOutsideCoverage(t *testing.T) {
	f, m := fixtures(t)
	depart := time.Date(2026, 10, 15, 20, 0, 0, 0, time.UTC)
	if _, err := build(f, m, depart, depart.Add(6*time.Hour)); !errors.Is(err, environment.ErrCoverage) {
		t.Fatalf("want environment.ErrCoverage, got %v", err)
	}
}

func TestNullIsNotZero(t *testing.T) {
	f, m := fixtures(t)
	m = []byte(strings.Replace(string(m), `"ocean_current_velocity":[0.60,0.60,0.60,0.66`, `"ocean_current_velocity":[0.60,0.60,0.60,null`, 1))
	depart := time.Date(2026, 10, 15, 3, 0, 0, 0, time.UTC)
	if _, err := build(f, m, depart, depart.Add(time.Hour)); !errors.Is(err, environment.ErrCoverage) {
		t.Fatalf("want environment.ErrCoverage, got %v", err)
	}
}

func TestWrongUnitRejected(t *testing.T) {
	f, m := fixtures(t)
	f = []byte(strings.Replace(string(f), `"wind_speed_10m":"m/s"`, `"wind_speed_10m":"km/h"`, 1))
	depart := time.Date(2026, 10, 15, 3, 0, 0, 0, time.UTC)
	if _, err := build(f, m, depart, depart.Add(time.Hour)); err == nil {
		t.Fatal("km/h must be rejected")
	}
}
