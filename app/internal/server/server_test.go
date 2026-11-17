package server

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestHealthAndRoot(t *testing.T) {
	srv := New("1.2.3")
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)

	health := get(t, ts.URL+"/healthz")
	if health.status != http.StatusOK || !strings.Contains(health.body, `"status":"ok"`) {
		t.Fatalf("healthz: status=%d body=%s", health.status, health.body)
	}

	ready := get(t, ts.URL+"/readyz")
	if ready.status != http.StatusOK || !strings.Contains(ready.body, `"status":"ready"`) {
		t.Fatalf("readyz: status=%d body=%s", ready.status, ready.body)
	}

	root := get(t, ts.URL+"/")
	if root.status != http.StatusOK || !strings.Contains(root.body, `"version":"1.2.3"`) {
		t.Fatalf("root: status=%d body=%s", root.status, root.body)
	}
}

func TestEchoAndErrorMetrics(t *testing.T) {
	srv := New("dev")
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)

	echo := get(t, ts.URL+"/api/echo")
	if echo.status != http.StatusOK {
		t.Fatalf("echo status=%d body=%s", echo.status, echo.body)
	}
	fault := get(t, ts.URL+"/api/error")
	if fault.status != http.StatusInternalServerError || !strings.Contains(fault.body, `"error":"sample fault"`) {
		t.Fatalf("error endpoint: status=%d body=%s", fault.status, fault.body)
	}
	missing := get(t, ts.URL+"/no-such")
	if missing.status != http.StatusNotFound {
		t.Fatalf("missing status=%d", missing.status)
	}

	if got := testutil.ToFloat64(srv.requests.WithLabelValues("GET", "/api/echo", "200")); got != 1 {
		t.Fatalf("echo counter = %v", got)
	}
	if got := testutil.ToFloat64(srv.requests.WithLabelValues("GET", "/api/error", "500")); got != 1 {
		t.Fatalf("error counter = %v", got)
	}
	if got := testutil.ToFloat64(srv.requests.WithLabelValues("GET", "unmatched", "404")); got != 1 {
		t.Fatalf("unmatched counter = %v", got)
	}

	metrics := get(t, ts.URL+"/metrics")
	if metrics.status != http.StatusOK {
		t.Fatalf("metrics status=%d", metrics.status)
	}
	for _, want := range []string{
		"http_requests_total",
		"http_request_duration_seconds_bucket",
		`path="/api/echo"`,
	} {
		if !strings.Contains(metrics.body, want) {
			t.Fatalf("metrics output missing %q", want)
		}
	}
	if got := testutil.ToFloat64(srv.requests.WithLabelValues("GET", "/metrics", "200")); got != 0 {
		t.Fatalf("metrics scrapes should not be counted, got %v", got)
	}
}

func TestSleepValidation(t *testing.T) {
	srv := New("dev")
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)

	bad := get(t, ts.URL+"/api/echo?sleep_ms=2001")
	if bad.status != http.StatusBadRequest {
		t.Fatalf("oversize sleep status=%d", bad.status)
	}
	badText := get(t, ts.URL+"/api/echo?sleep_ms=nope")
	if badText.status != http.StatusBadRequest {
		t.Fatalf("invalid sleep status=%d", badText.status)
	}
	ok := get(t, ts.URL+"/api/echo?sleep_ms=1")
	if ok.status != http.StatusOK {
		t.Fatalf("small sleep status=%d", ok.status)
	}
}

type response struct {
	status int
	body   string
}

func get(t *testing.T, url string) response {
	t.Helper()
	res, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response{status: res.StatusCode, body: string(body)}
}
