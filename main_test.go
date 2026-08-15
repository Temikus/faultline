package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// The whole value of this image is that it fails exactly as much as it claims
// to. A profile tag built with FAIL_RATE=0.35 that served 200s would send
// whatever is under test to the wrong conclusion, and the test would look like
// the bug. These check both ends of the dial.

func TestHandlerNeverFailsAtZeroRate(t *testing.T) {
	h := handler(0, 0)
	for i := 0; i < 50; i++ {
		if got := status(h); got != http.StatusOK {
			t.Fatalf("request %d: got %d, want 200", i, got)
		}
	}
}

func TestHandlerAlwaysFailsAtRateOne(t *testing.T) {
	h := handler(1, 0)
	for i := 0; i < 50; i++ {
		if got := status(h); got != http.StatusInternalServerError {
			t.Fatalf("request %d: got %d, want 500", i, got)
		}
	}
}

func TestHandlerWaitsForLatency(t *testing.T) {
	const latency = 20 * time.Millisecond
	start := time.Now()
	status(handler(0, latency))
	if elapsed := time.Since(start); elapsed < latency {
		t.Fatalf("returned after %s, want at least %s", elapsed, latency)
	}
}

// TestEnvFloatFallsBackRatherThanFailing pins the deliberate choice in
// envFloat: a typo in a manifest yields a healthy app, not one that will not
// boot.
func TestEnvFloatFallsBackRatherThanFailing(t *testing.T) {
	t.Setenv("FAIL_RATE", "not-a-number")
	if got := envFloat("FAIL_RATE", 0.5); got != 0.5 {
		t.Fatalf("got %v, want the fallback 0.5", got)
	}

	t.Setenv("FAIL_RATE", "0.35")
	if got := envFloat("FAIL_RATE", 0); got != 0.35 {
		t.Fatalf("got %v, want 0.35", got)
	}
}

func status(h http.HandlerFunc) int {
	w := httptest.NewRecorder()
	h(w, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	return w.Code
}
