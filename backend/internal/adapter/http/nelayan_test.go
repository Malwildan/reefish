package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"nelayan-route/internal/auth"
	"nelayan-route/internal/domain/weather"
	"nelayan-route/internal/usecase/nelayan"
)

type fakeNelayan struct {
	err      error
	gotToken string
	refresh  bool
}

func (f *fakeNelayan) Recommendations(ctx context.Context, _ string, refresh bool) (json.RawMessage, error) {
	f.gotToken, f.refresh = auth.Token(ctx), refresh
	if f.err != nil {
		return nil, f.err
	}
	return json.RawMessage(`{"items":[]}`), nil
}

func (f *fakeNelayan) Weather(ctx context.Context, _, _, _ string) (*weather.Report, error) {
	f.gotToken = auth.Token(ctx)
	if f.err != nil {
		return nil, f.err
	}
	return &weather.Report{}, nil
}

func (f *fakeNelayan) WeatherArea(ctx context.Context, _, _ string) (*weather.Area, error) {
	f.gotToken = auth.Token(ctx)
	if f.err != nil {
		return nil, f.err
	}
	return &weather.Area{}, nil
}

func TestNelayanStatusMapping(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		name, path, auth string
		err              error
		want             int
	}{
		{"no token", "/api/v1/recommendations", "", nil, 401},
		{"bad refresh", "/api/v1/recommendations?refresh=yes", "Bearer t", nil, 400},
		{"ok", "/api/v1/recommendations?refresh=true", "Bearer t", nil, 200},
		{"weather ok", "/api/v1/weather?lat=1&lng=2", "Bearer t", nil, 200},
		{"area ok", "/api/v1/weather/area", "Bearer t", nil, 200},
		{"area bad bbox", "/api/v1/weather/area?bbox=x", "Bearer t", &nelayan.Error{Code: "VALIDATION_ERROR"}, 400},
		{"validation", "/api/v1/weather", "Bearer t", &nelayan.Error{Code: "VALIDATION_ERROR"}, 400},
		{"forbidden", "/api/v1/recommendations", "Bearer t", &nelayan.Error{Code: "FORBIDDEN"}, 403},
		{"onboarding", "/api/v1/recommendations", "Bearer t", &nelayan.Error{Code: "ONBOARDING_REQUIRED"}, 409},
		{"pilot", "/api/v1/weather", "Bearer t", &nelayan.Error{Code: "OUT_OF_PILOT"}, 422},
		{"expired", "/api/v1/weather", "Bearer t", &nelayan.Error{Code: "UNAUTHORIZED"}, 401},
		{"weather down", "/api/v1/weather", "Bearer t", &nelayan.Error{Code: "WEATHER_UNAVAILABLE"}, 503},
		{"unknown code", "/api/v1/weather", "Bearer t", &nelayan.Error{Code: "SOMETHING"}, 500},
		{"upstream", "/api/v1/weather", "Bearer t", errors.New("connection refused"), 503},
	}
	for _, tc := range cases {
		f := &fakeNelayan{err: tc.err}
		req := httptest.NewRequest(http.MethodGet, tc.path, nil)
		if tc.auth != "" {
			req.Header.Set("Authorization", tc.auth)
		}
		w := httptest.NewRecorder()
		NewRouter(nil, f, "").ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Errorf("%s: status %d, want %d: %s", tc.name, w.Code, tc.want, w.Body)
		}
		if tc.want == 200 {
			if f.gotToken != "t" {
				t.Errorf("%s: token not forwarded: %q", tc.name, f.gotToken)
			}
			var body struct{ Data json.RawMessage }
			if json.Unmarshal(w.Body.Bytes(), &body) != nil || len(body.Data) == 0 {
				t.Errorf("%s: missing data envelope: %s", tc.name, w.Body)
			}
		} else {
			var body struct{ Error struct{ Code string } }
			if json.Unmarshal(w.Body.Bytes(), &body) != nil || body.Error.Code == "" {
				t.Errorf("%s: missing error body: %s", tc.name, w.Body)
			}
		}
	}
}
