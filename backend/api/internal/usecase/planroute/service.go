// Package planroute is the round-trip fuel route use case (spec 8.7, 10.1, 12.5–12.9).
// It depends only on the domain and on the ports below; adapters implement the ports.
package planroute

import (
	"context"
	"errors"
	"time"

	"nelayan-route/internal/domain/environment"
	"nelayan-route/internal/domain/routing"
)

type GridRepository interface {
	Grid(ctx context.Context) (*routing.Grid, error)
}

type ZoneRepository interface {
	// ClosedZones returns closed zones active at any time in [from, to].
	ClosedZones(ctx context.Context, from, to time.Time) ([]routing.Polygon, error)
}

type EnvironmentProvider interface {
	Fetch(ctx context.Context, lat, lon float64, from, to time.Time) (environment.Environment, error)
}

type Service struct {
	Grid    GridRepository
	Zones   ZoneRepository
	Weather EnvironmentProvider
}

// Plan validates the request, loads every input, and computes the round trip.
func (s Service) Plan(ctx context.Context, r *Request) (*Result, *Error) {
	if e := r.Validate(); e != nil {
		return nil, e
	}
	// Zones first: with the caller's token they also reject unauthenticated requests early.
	closed, err := s.Zones.ClosedZones(ctx, r.DepartAt, r.LatestReturnAt)
	if err != nil {
		return nil, dependency(err)
	}
	grid, err := s.Grid.Grid(ctx)
	if err != nil {
		return nil, dependency(err)
	}
	env, err := s.Weather.Fetch(ctx, r.Destination.Lat, r.Destination.Lon, r.DepartAt, r.LatestReturnAt)
	if err != nil {
		if errors.Is(err, environment.ErrCoverage) {
			return nil, &Error{Kind: KindInvalid, Code: "ENVIRONMENT_COVERAGE_GAP", Message: err.Error(), cause: err}
		}
		return nil, dependency(err)
	}
	return compute(r, grid, closed, env)
}

func dependency(err error) *Error {
	if errors.Is(err, ErrUnauthenticated) {
		return &Error{Kind: KindUnauthenticated, Code: "UNAUTHENTICATED", Message: "invalid or expired token", cause: err}
	}
	return &Error{Kind: KindUnavailable, Code: "PROVIDER_UNAVAILABLE", Message: "upstream data source unavailable", cause: err}
}
