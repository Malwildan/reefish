// Package httpapi is the Gin delivery layer: decoding, auth header, error-to-status mapping.
package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"nelayan-route/internal/auth"
	"nelayan-route/internal/usecase/planroute"
)

const maxBody = 1 << 20

type RoutePlanner interface {
	Plan(ctx context.Context, r *planroute.Request) (*planroute.Result, *planroute.Error)
}

type handler struct{ planner RoutePlanner }

var statusOf = map[planroute.Kind]int{
	planroute.KindInvalid:         http.StatusUnprocessableEntity,
	planroute.KindUnauthenticated: http.StatusUnauthorized,
	planroute.KindUnavailable:     http.StatusServiceUnavailable,
}

func abort(c *gin.Context, status int, e *planroute.Error) {
	c.AbortWithStatusJSON(status, gin.H{"error": e, "request_id": c.GetString(requestIDKey)})
}

func (h handler) createRoute(c *gin.Context) {
	token, ok := strings.CutPrefix(c.GetHeader("Authorization"), "Bearer ")
	if !ok || token == "" {
		abort(c, http.StatusUnauthorized, &planroute.Error{Code: "UNAUTHENTICATED", Message: "Bearer token required"})
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(c.Writer, c.Request.Body, maxBody))
	if err != nil {
		abort(c, http.StatusBadRequest, &planroute.Error{Code: "INVALID_JSON", Message: err.Error()})
		return
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.DisallowUnknownFields()
	var req planroute.Request
	if err := dec.Decode(&req); err != nil || dec.More() {
		code, msg := "INVALID_JSON", "trailing data after JSON object"
		if err != nil {
			msg = err.Error()
			if strings.Contains(msg, "unknown field") {
				code = "UNKNOWN_FIELD"
			}
		}
		abort(c, http.StatusBadRequest, &planroute.Error{Code: code, Message: msg})
		return
	}

	res, e := h.planner.Plan(auth.WithToken(c.Request.Context(), token), &req)
	if e != nil {
		if e.Kind == planroute.KindUnavailable {
			slog.Error("dependency failure", "err", e.Unwrap(), "request_id", c.GetString(requestIDKey))
		}
		abort(c, statusOf[e.Kind], e)
		return
	}
	c.JSON(http.StatusOK, gin.H{"route": res, "request_id": c.GetString(requestIDKey)})
}
