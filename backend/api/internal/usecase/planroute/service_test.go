package planroute

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"nelayan-route/internal/domain/environment"
	"nelayan-route/internal/domain/routing"
)

type fakeGrid struct{ g *routing.Grid }

func (f fakeGrid) Grid(context.Context) (*routing.Grid, error) { return f.g, nil }

type fakeZones struct{ err error }

func (f fakeZones) ClosedZones(context.Context, time.Time, time.Time) ([]routing.Polygon, error) {
	return nil, f.err
}

type fakeWeather struct{ err error }

func (f fakeWeather) Fetch(context.Context, float64, float64, time.Time, time.Time) (environment.Environment, error) {
	return environment.Environment{}, f.err
}

func TestServiceMapsDependencyErrors(t *testing.T) {
	cases := []struct {
		zones, weather error
		kind           Kind
		code           string
	}{
		{fmt.Errorf("401: %w", ErrUnauthenticated), nil, KindUnauthenticated, "UNAUTHENTICATED"},
		{errors.New("timeout"), nil, KindUnavailable, "PROVIDER_UNAVAILABLE"},
		{nil, fmt.Errorf("x: %w", environment.ErrCoverage), KindInvalid, "ENVIRONMENT_COVERAGE_GAP"},
	}
	for _, tc := range cases {
		s := Service{fakeGrid{grid(5)}, fakeZones{tc.zones}, fakeWeather{tc.weather}}
		_, e := s.Plan(context.Background(), request(t))
		if e == nil || e.Kind != tc.kind || e.Code != tc.code {
			t.Errorf("want %v %s, got %+v", tc.kind, tc.code, e)
		}
	}
}

func TestServiceSucceeds(t *testing.T) {
	s := Service{fakeGrid{grid(5)}, fakeZones{}, fakeWeather{}}
	res, e := s.Plan(context.Background(), request(t))
	if e != nil || res.Status != "succeeded" {
		t.Fatalf("got %+v %v", res, e)
	}
}
