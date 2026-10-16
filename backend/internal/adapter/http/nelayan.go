package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"nelayan-route/internal/auth"
	"nelayan-route/internal/domain/weather"
	"nelayan-route/internal/usecase/nelayan"
)

// Nelayan is the computation part of the fisher API; data endpoints are Supabase RPCs.
type Nelayan interface {
	Recommendations(ctx context.Context, forDate string, refresh bool) (json.RawMessage, error)
	Weather(ctx context.Context, lat, lng, hours string) (*weather.Report, error)
	WeatherArea(ctx context.Context, bbox, hours string) (*weather.Area, error)
}

var nelayanStatus = map[string]int{
	"VALIDATION_ERROR":    http.StatusBadRequest,
	"UNAUTHORIZED":        http.StatusUnauthorized,
	"FORBIDDEN":           http.StatusForbidden,
	"ONBOARDING_REQUIRED": http.StatusConflict,
	"OUT_OF_PILOT":        http.StatusUnprocessableEntity,
	"WEATHER_UNAVAILABLE": http.StatusServiceUnavailable,
}

type nelayanHandler struct{ svc Nelayan }

// bearer requires a Supabase access token and hands it to the data adapter via context.
func bearer(c *gin.Context) {
	token, ok := strings.CutPrefix(c.GetHeader("Authorization"), "Bearer ")
	if !ok || token == "" {
		fail(c, &nelayan.Error{Code: "UNAUTHORIZED", Message: "Bearer token required"})
		return
	}
	c.Request = c.Request.WithContext(auth.WithToken(c.Request.Context(), token))
	c.Next()
}

func fail(c *gin.Context, err error) {
	var e *nelayan.Error
	if !errors.As(err, &e) {
		slog.Error("dependency failure", "err", err, "request_id", c.GetString(requestIDKey))
		e = &nelayan.Error{Code: "UPSTREAM_UNAVAILABLE", Message: "Layanan data sedang bermasalah, coba lagi"}
	} else if e.Unwrap() != nil {
		slog.Warn("upstream error", "code", e.Code, "err", e.Unwrap(), "request_id", c.GetString(requestIDKey))
	}
	status, ok := nelayanStatus[e.Code]
	if !ok {
		status = http.StatusServiceUnavailable
		if e.Code != "UPSTREAM_UNAVAILABLE" {
			status = http.StatusInternalServerError
		}
	}
	c.AbortWithStatusJSON(status, gin.H{"error": e, "request_id": c.GetString(requestIDKey)})
}

func (h nelayanHandler) recommendations(c *gin.Context) {
	refresh := c.Query("refresh")
	if refresh != "" && refresh != "true" && refresh != "false" {
		fail(c, &nelayan.Error{Code: "VALIDATION_ERROR", Message: "refresh harus true atau false"})
		return
	}
	set, err := h.svc.Recommendations(c.Request.Context(), c.Query("for_date"), refresh == "true")
	if err != nil {
		fail(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": set})
}

func (h nelayanHandler) weather(c *gin.Context) {
	rep, err := h.svc.Weather(c.Request.Context(), c.Query("lat"), c.Query("lng"), c.Query("hours"))
	if err != nil {
		fail(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": rep})
}

func (h nelayanHandler) weatherArea(c *gin.Context) {
	area, err := h.svc.WeatherArea(c.Request.Context(), c.Query("bbox"), c.Query("hours"))
	if err != nil {
		fail(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": area})
}
