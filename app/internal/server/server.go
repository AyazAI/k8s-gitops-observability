// Package server is the HTTP service used by the portfolio sample.
// It exposes health checks and Prometheus metrics for the GitOps demo.
package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const maxSleep = 2 * time.Second

// Server is an HTTP handler with its own Prometheus registry.
type Server struct {
	version  string
	registry *prometheus.Registry
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
}

// New builds a server that records request counts and latency.
func New(version string) *Server {
	registry := prometheus.NewRegistry()
	requests := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "HTTP requests processed, partitioned by method, path, and status code.",
	}, []string{"method", "path", "code"})
	duration := prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request duration in seconds, partitioned by method and path.",
		Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5},
	}, []string{"method", "path"})

	registry.MustRegister(
		requests,
		duration,
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)

	return &Server{
		version:  version,
		registry: registry,
		requests: requests,
		duration: duration,
	}
}

type pathKey struct{}

// Handler returns the service routes wrapped with metrics.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	s.route(mux, "GET /{$}", "/", s.root)
	s.route(mux, "GET /healthz", "/healthz", s.health)
	s.route(mux, "GET /readyz", "/readyz", s.ready)
	s.route(mux, "GET /api/echo", "/api/echo", s.echo)
	s.route(mux, "GET /api/error", "/api/error", s.sampleError)
	mux.Handle("GET /metrics", promhttp.HandlerFor(s.registry, promhttp.HandlerOpts{}))
	return s.instrument(mux)
}

func (s *Server) route(mux *http.ServeMux, pattern, label string, handler http.HandlerFunc) {
	mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		if labelPtr, ok := r.Context().Value(pathKey{}).(*string); ok {
			*labelPtr = label
		}
		handler(w, r)
	})
}

func (s *Server) instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		path := "unmatched"
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		ctx := context.WithValue(r.Context(), pathKey{}, &path)
		next.ServeHTTP(sw, r.WithContext(ctx))

		elapsed := time.Since(start).Seconds()
		s.duration.WithLabelValues(r.Method, path).Observe(elapsed)
		s.requests.WithLabelValues(r.Method, path, strconv.Itoa(sw.status)).Inc()
		log.Printf("%s %s %d %.3fs", r.Method, path, sw.status, elapsed)
	})
}

func (s *Server) root(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "portfolio-sample",
		"version": s.version,
	})
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) ready(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) echo(w http.ResponseWriter, r *http.Request) {
	if raw := r.URL.Query().Get("sleep_ms"); raw != "" {
		ms, err := strconv.Atoi(raw)
		if err != nil || ms < 0 || time.Duration(ms)*time.Millisecond > maxSleep {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "sleep_ms must be an integer between 0 and 2000",
			})
			return
		}
		if ms > 0 {
			time.Sleep(time.Duration(ms) * time.Millisecond)
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "portfolio-sample",
		"version": s.version,
		"path":    "/api/echo",
	})
}

func (s *Server) sampleError(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusInternalServerError, map[string]string{
		"error": "sample fault",
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("write json: %v", err)
	}
}

type statusWriter struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (w *statusWriter) WriteHeader(status int) {
	if w.wrote {
		return
	}
	w.status = status
	w.wrote = true
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if !w.wrote {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(b)
}
