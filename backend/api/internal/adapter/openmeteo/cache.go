package openmeteo

import (
	"context"
	"fmt"
	"math"
	"sync"
	"time"

	"nelayan-route/internal/domain/environment"
	"nelayan-route/internal/domain/weather"
)

// Cached wraps Provider with an in-memory TTL cache so repeated map pans, recommendations and route
// plans for nearby points do not each call Open-Meteo. Only successful responses are stored.
// shortcut: per-process cache; use a shared store (e.g. a weather_cache table) once Cloud Run runs
// many instances and Open-Meteo rate limits start to matter.
type Cached struct {
	Provider Provider
	TTL      time.Duration // default 30 min
	Max      int           // default 512 entries
	Now      func() time.Time

	mu      sync.Mutex
	entries map[string]cacheEntry
}

type cacheEntry struct {
	val     any
	expires time.Time
}

func (c *Cached) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// round2 groups points ~1 km apart: Open-Meteo answers on a coarser grid anyway.
func round2(v float64) float64 { return math.Round(v*100) / 100 }

func (c *Cached) get(key string) (any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || !c.now().Before(e.expires) {
		return nil, false
	}
	return e.val, true
}

func (c *Cached) put(key string, val any) {
	ttl, max := c.TTL, c.Max
	if ttl <= 0 {
		ttl = 30 * time.Minute
	}
	if max <= 0 {
		max = 512
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.entries == nil {
		c.entries = map[string]cacheEntry{}
	}
	now := c.now()
	if len(c.entries) >= max {
		oldest := ""
		for k, e := range c.entries {
			if !now.Before(e.expires) {
				delete(c.entries, k)
				continue
			}
			if oldest == "" || e.expires.Before(c.entries[oldest].expires) {
				oldest = k
			}
		}
		if len(c.entries) >= max && oldest != "" {
			delete(c.entries, oldest)
		}
	}
	c.entries[key] = cacheEntry{val: val, expires: now.Add(ttl)}
}

type pointResult struct {
	loc   weather.Location
	hours []weather.Hour
}

func cloneHours(hours []weather.Hour) []weather.Hour {
	clone := append([]weather.Hour(nil), hours...)
	for i := range clone {
		if hours[i].WeatherCode != nil {
			v := *hours[i].WeatherCode
			clone[i].WeatherCode = &v
		}
		if hours[i].WeatherLabel != nil {
			v := *hours[i].WeatherLabel
			clone[i].WeatherLabel = &v
		}
		if hours[i].TempC != nil {
			v := *hours[i].TempC
			clone[i].TempC = &v
		}
		if hours[i].WindSpeedMs != nil {
			v := *hours[i].WindSpeedMs
			clone[i].WindSpeedMs = &v
		}
		if hours[i].WindDirDeg != nil {
			v := *hours[i].WindDirDeg
			clone[i].WindDirDeg = &v
		}
		if hours[i].WindDirLabel != nil {
			v := *hours[i].WindDirLabel
			clone[i].WindDirLabel = &v
		}
		if hours[i].WaveHeightM != nil {
			v := *hours[i].WaveHeightM
			clone[i].WaveHeightM = &v
		}
	}
	return clone
}

// Point implements nelayan.Forecaster. Callers get their own copy of the hours (Enrich mutates them).
func (c *Cached) Point(ctx context.Context, lat, lng float64, from time.Time, hours int) (weather.Location, []weather.Hour, error) {
	key := fmt.Sprintf("p|%.2f|%.2f|%d|%d", round2(lat), round2(lng), from.UTC().Truncate(time.Hour).Unix(), hours)
	if v, ok := c.get(key); ok {
		r := v.(pointResult)
		return r.loc, cloneHours(r.hours), nil
	}
	loc, hs, err := c.Provider.Point(ctx, lat, lng, from, hours)
	if err != nil {
		return loc, hs, err
	}
	c.put(key, pointResult{loc, cloneHours(hs)})
	return loc, hs, nil
}

func (c *Cached) Area(ctx context.Context, pts []weather.Location, at time.Time) ([]weather.Hour, error) {
	key := fmt.Sprintf("a|%d", at.UTC().Truncate(time.Hour).Unix())
	for _, p := range pts {
		key += fmt.Sprintf("|%.2f,%.2f", round2(p.Lat), round2(p.Lng))
	}
	if v, ok := c.get(key); ok {
		return cloneHours(v.([]weather.Hour)), nil
	}
	hs, err := c.Provider.Area(ctx, pts, at)
	if err != nil {
		return hs, err
	}
	c.put(key, cloneHours(hs))
	return hs, nil
}

// Fetch implements planroute.EnvironmentProvider.
func (c *Cached) Fetch(ctx context.Context, lat, lon float64, depart, latestReturn time.Time) (environment.Environment, error) {
	key := fmt.Sprintf("f|%.2f|%.2f|%d|%d", round2(lat), round2(lon), depart.UTC().Truncate(time.Hour).Unix(),
		latestReturn.UTC().Truncate(time.Hour).Unix())
	if v, ok := c.get(key); ok {
		return v.(environment.Environment), nil
	}
	env, err := c.Provider.Fetch(ctx, lat, lon, depart, latestReturn)
	if err != nil {
		return env, err
	}
	c.put(key, env)
	return env, nil
}
