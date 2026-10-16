package openmeteo

import (
	"context"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// stub answers forecast/marine requests with the point fixtures and counts calls.
type stub struct {
	calls atomic.Int32
	fail  bool
}

func (s *stub) RoundTrip(r *http.Request) (*http.Response, error) {
	s.calls.Add(1)
	body, code := pointForecast, 200
	if strings.Contains(r.URL.Host, "marine") {
		body = pointMarine
	}
	if s.fail {
		body, code = `{"error":true,"reason":"down"}`, 500
	}
	return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
}

func TestCachedPoint(t *testing.T) {
	s := &stub{}
	now := time.Date(2026, 10, 16, 5, 0, 0, 0, time.UTC)
	c := &Cached{Provider: Provider{HTTP: &http.Client{Transport: s}}, Now: func() time.Time { return now }}
	ctx := context.Background()

	_, hs, err := c.Point(ctx, -8.401, 112.601, now, 2)
	if err != nil || len(hs) != 2 {
		t.Fatal(err, hs)
	}
	first := s.calls.Load()
	hs[0].Risk = "mutated"
	*hs[0].TempC = -999
	_, again, _ := c.Point(ctx, -8.4012, 112.6008, now.Add(10*time.Minute), 2) // same 0.01° cell, same hour
	if s.calls.Load() != first {
		t.Fatalf("hit must not call HTTP: %d -> %d", first, s.calls.Load())
	}
	if again[0].Risk == "mutated" {
		t.Fatal("cached hours must be copied")
	}
	if *again[0].TempC != 28.1 {
		t.Fatal("cached values must not share mutable pointers")
	}
	if _, _, _ = c.Point(ctx, -8.5, 112.6, now, 2); s.calls.Load() == first {
		t.Fatal("other cell must miss")
	}

	now = now.Add(31 * time.Minute)
	before := s.calls.Load()
	c.Point(ctx, -8.401, 112.601, time.Date(2026, 10, 16, 5, 0, 0, 0, time.UTC), 2)
	if s.calls.Load() == before {
		t.Fatal("expired entry must refetch")
	}
}

func TestCachedSkipsErrorsAndEvicts(t *testing.T) {
	s := &stub{fail: true}
	now := time.Date(2026, 10, 16, 5, 0, 0, 0, time.UTC)
	c := &Cached{Provider: Provider{HTTP: &http.Client{Transport: s}}, Max: 2, Now: func() time.Time { return now }}
	ctx := context.Background()
	if _, _, err := c.Point(ctx, -8.4, 112.6, now, 2); err == nil {
		t.Fatal("expected error")
	}
	s.fail = false
	if _, _, err := c.Point(ctx, -8.4, 112.6, now, 2); err != nil {
		t.Fatal("error must not be cached:", err)
	}
	c.Point(ctx, -8.5, 112.6, now, 2)
	c.Point(ctx, -8.6, 112.6, now, 2)
	if len(c.entries) != 2 {
		t.Fatalf("entries = %d, want max 2", len(c.entries))
	}
}
