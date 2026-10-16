package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"nelayan-route/internal/auth"
	"nelayan-route/internal/usecase/planroute"
)

type fakePlanner struct {
	err      *planroute.Error
	gotToken string
}

func (f *fakePlanner) Plan(ctx context.Context, _ *planroute.Request) (*planroute.Result, *planroute.Error) {
	f.gotToken = auth.Token(ctx)
	if f.err != nil {
		return nil, f.err
	}
	return &planroute.Result{Status: "succeeded"}, nil
}

func TestCreateRouteStatusMapping(t *testing.T) {
	gin.SetMode(gin.TestMode)
	cases := []struct {
		name, auth, body string
		err              *planroute.Error
		want             int
	}{
		{"no token", "", `{}`, nil, 401},
		{"unknown field", "Bearer t", `{"nope":1}`, nil, 400},
		{"trailing json", "Bearer t", `{} {}`, nil, 400},
		{"invalid", "Bearer t", `{}`, &planroute.Error{Kind: planroute.KindInvalid, Code: "X"}, 422},
		{"unauthenticated", "Bearer t", `{}`, &planroute.Error{Kind: planroute.KindUnauthenticated, Code: "X"}, 401},
		{"unavailable", "Bearer t", `{}`, &planroute.Error{Kind: planroute.KindUnavailable, Code: "X"}, 503},
		{"ok", "Bearer t", `{}`, nil, 200},
	}
	for _, tc := range cases {
		p := &fakePlanner{err: tc.err}
		req := httptest.NewRequest(http.MethodPost, "/v1/routes", strings.NewReader(tc.body))
		if tc.auth != "" {
			req.Header.Set("Authorization", tc.auth)
		}
		w := httptest.NewRecorder()
		NewRouter(p, nil, "").ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Errorf("%s: status %d, want %d: %s", tc.name, w.Code, tc.want, w.Body)
		}
		if tc.want == 200 && p.gotToken != "t" {
			t.Errorf("token not forwarded via context: %q", p.gotToken)
		}
	}
}
