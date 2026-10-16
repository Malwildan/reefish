// Package supabase implements the planroute repositories over PostgREST with the caller's JWT,
// so RLS also authenticates the request.
package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

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

// send makes a request as the caller (anon key + user JWT) and returns status and body.
func (c *Client) send(ctx context.Context, method, path string, body io.Reader) (int, []byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, c.URL+path, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("apikey", c.AnonKey)
	req.Header.Set("Authorization", "Bearer "+auth.Token(ctx))
	if method == http.MethodPost {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return 0, nil, fmt.Errorf("supabase %s: %w", path, err)
	}
	defer res.Body.Close()
	b, err := io.ReadAll(io.LimitReader(res.Body, 32<<20))
	if err != nil {
		return 0, nil, fmt.Errorf("supabase %s: %w", path, err)
	}
	return res.StatusCode, b, nil
}

func (c *Client) do(ctx context.Context, method, path string, out any) error {
	status, body, err := c.send(ctx, method, path, nil)
	if err != nil {
		return err
	}
	switch {
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return fmt.Errorf("supabase %s: HTTP %d: %w", path, status, planroute.ErrUnauthenticated)
	case status != http.StatusOK:
		return fmt.Errorf("supabase %s: HTTP %d: %.200s", path, status, body)
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

// ClosedZones returns zones closed at any time in [from, to] (spec 3: conservative over the window):
// rehab zones and restricted zones whose quota is used up, via the closed_zone_outlines RPC.
func (c *Client) ClosedZones(ctx context.Context, from, to time.Time) ([]routing.Polygon, error) {
	body, _ := json.Marshal(map[string]string{"p_from": from.UTC().Format(time.RFC3339), "p_to": to.UTC().Format(time.RFC3339)})
	status, res, err := c.send(ctx, http.MethodPost, "/rest/v1/rpc/closed_zone_outlines", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	switch {
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return nil, fmt.Errorf("supabase closed_zone_outlines: HTTP %d: %w", status, planroute.ErrUnauthenticated)
	case status != http.StatusOK:
		return nil, fmt.Errorf("supabase closed_zone_outlines: HTTP %d: %.200s", status, res)
	}
	return parseOutlines(res)
}

// parseOutlines turns a JSON array of GeoJSON MultiPolygons into one routing polygon per part.
func parseOutlines(b []byte) ([]routing.Polygon, error) {
	var outlines []struct {
		Coordinates [][][][2]float64 `json:"coordinates"`
	}
	if err := json.Unmarshal(b, &outlines); err != nil {
		return nil, err
	}
	var polys []routing.Polygon
	for _, o := range outlines {
		for _, poly := range o.Coordinates {
			rings := make([][]routing.Point, len(poly))
			for i, ring := range poly {
				for _, p := range ring {
					rings[i] = append(rings[i], routing.Point{Lon: p[0], Lat: p[1]})
				}
			}
			polys = append(polys, routing.NewPolygon(rings))
		}
	}
	return polys, nil
}
