// Package supabase implements the planroute repositories over PostgREST with the caller's JWT,
// so RLS also authenticates the request.
package supabase

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"

	"nelayan-route/internal/auth"
	"nelayan-route/internal/domain/routing"
	"nelayan-route/internal/usecase/planroute"
)

type Client struct {
	URL     string // https://<ref>.supabase.co
	AnonKey string
	HTTP    *http.Client

	mu   sync.Mutex
	grid *routing.Grid
}

func (c *Client) do(ctx context.Context, method, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, method, c.URL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("apikey", c.AnonKey)
	req.Header.Set("Authorization", "Bearer "+auth.Token(ctx))
	if method == http.MethodPost {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("supabase %s: %w", path, err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 32<<20))
	if err != nil {
		return fmt.Errorf("supabase %s: %w", path, err)
	}
	switch {
	case res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden:
		return fmt.Errorf("supabase %s: HTTP %d: %w", path, res.StatusCode, planroute.ErrUnauthenticated)
	case res.StatusCode != http.StatusOK:
		return fmt.Errorf("supabase %s: HTTP %d: %.200s", path, res.StatusCode, body)
	}
	return json.Unmarshal(body, out)
}

// Grid loads all sea cells once via the grid_points() RPC; a failed load is retried next call.
func (c *Client) Grid(ctx context.Context) (*routing.Grid, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.grid != nil {
		return c.grid, nil
	}
	var rows [][3]json.RawMessage
	if err := c.do(ctx, http.MethodPost, "/rest/v1/rpc/grid_points", &rows); err != nil {
		return nil, err
	}
	cells := make([]routing.Cell, 0, len(rows))
	for _, r := range rows {
		var cell routing.Cell
		if err := json.Unmarshal(r[0], &cell.ID); err != nil {
			return nil, err
		}
		if _, err := fmt.Sscanf(cell.ID, "X%d_Y%d", &cell.X, &cell.Y); err != nil {
			return nil, fmt.Errorf("grid_id %q: %w", cell.ID, err)
		}
		if err := json.Unmarshal(r[1], &cell.Lon); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(r[2], &cell.Lat); err != nil {
			return nil, err
		}
		cells = append(cells, cell)
	}
	if len(cells) == 0 {
		return nil, errors.New("grid_points returned no cells; import data first")
	}
	c.grid = routing.NewGrid(cells)
	return c.grid, nil
}

// ClosedZones returns closed zones active at any time in [from, to] (spec 3: conservative over the window).
func (c *Client) ClosedZones(ctx context.Context, from, to time.Time) ([]routing.Polygon, error) {
	q := url.Values{
		"select":     {"geojson"},
		"status":     {"eq.closed"},
		"valid_from": {"lte." + to.UTC().Format("2006-01-02")},
		"or":         {"(valid_to.is.null,valid_to.gte." + from.UTC().Format("2006-01-02") + ")"},
	}
	var rows []struct {
		GeoJSON struct {
			Coordinates [][][2]float64 `json:"coordinates"`
		} `json:"geojson"`
	}
	if err := c.do(ctx, http.MethodGet, "/rest/v1/zones?"+q.Encode(), &rows); err != nil {
		return nil, err
	}
	polys := make([]routing.Polygon, 0, len(rows))
	for _, r := range rows {
		rings := make([][]routing.Point, len(r.GeoJSON.Coordinates))
		for i, ring := range r.GeoJSON.Coordinates {
			for _, p := range ring {
				rings[i] = append(rings[i], routing.Point{Lon: p[0], Lat: p[1]})
			}
		}
		polys = append(polys, routing.NewPolygon(rings))
	}
	return polys, nil
}
