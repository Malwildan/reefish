package httpapi

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

const requestIDKey = "request_id"

// NewRouter wires routes and middleware. allowedOrigin "" allows any origin.
func NewRouter(planner RoutePlanner, fisher Nelayan, allowedOrigin string) *gin.Engine {
	r := gin.New()
	r.Use(requestID, gin.Recovery(), gin.Logger(), cors(allowedOrigin))
	r.GET("/health/live", func(c *gin.Context) { c.Status(http.StatusOK) })
	r.POST("/v1/routes", handler{planner}.createRoute)

	v1 := r.Group("/api/v1", bearer)
	h := nelayanHandler{fisher}
	v1.GET("/recommendations", h.recommendations)
	v1.GET("/weather", h.weather)
	v1.GET("/weather/area", h.weatherArea)
	return r
}

func requestID(c *gin.Context) {
	id := c.GetHeader("X-Request-ID")
	if id == "" || len(id) > 64 {
		id = time.Now().UTC().Format("20060102T150405.000000000")
	}
	c.Set(requestIDKey, id)
	c.Header("X-Request-ID", id)
}

// cors lets the browser frontend call the API with its Supabase JWT.
// shortcut: empty origin means "*"; set ALLOWED_ORIGIN before a public deploy.
func cors(origin string) gin.HandlerFunc {
	if origin == "" {
		origin = "*"
	}
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", origin)
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
		c.Header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
