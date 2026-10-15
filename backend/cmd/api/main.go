// Command api serves POST /v1/routes: synchronous static_snapshot round-trip planning.
// Supabase owns auth and data; this binary only wires adapters to the use case.
package main

import (
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	httpapi "nelayan-route/internal/adapter/http"
	"nelayan-route/internal/adapter/openmeteo"
	"nelayan-route/internal/adapter/supabase"
	"nelayan-route/internal/usecase/planroute"
)

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		slog.Error("missing env", "key", k)
		os.Exit(1)
	}
	return v
}

func main() {
	client := &http.Client{Timeout: 10 * time.Second}
	db := &supabase.Client{URL: strings.TrimRight(mustEnv("SUPABASE_URL"), "/"), AnonKey: mustEnv("SUPABASE_ANON_KEY"), HTTP: client}
	planner := planroute.Service{Grid: db, Zones: db, Weather: openmeteo.Provider{HTTP: client}}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           httpapi.NewRouter(planner, os.Getenv("ALLOWED_ORIGIN")),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	slog.Info("listening", "port", port)
	if err := srv.ListenAndServe(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
