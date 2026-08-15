// Command faultline is an HTTP server that fails on purpose.
//
// It exists to be the thing under test when what you are testing is how a
// system reacts to partial failure: a canary that ought to be rolled back, an
// alert that ought to fire, a load balancer that ought to shed a bad backend.
// Two numbers describe it — how often it returns 500, and how slow it is.
//
// Both can be set two ways, and which you want depends on what you are testing.
// Set FAIL_RATE and LATENCY_MS at run time for a server you tune in place. Or
// deploy one of the pre-baked profile tags, where the behaviour is built into
// the image, so the tag that was deployed is a complete account of what the
// workload does — which is what you want when the system under test is a
// pipeline deciding things from what it observes, and a manifest holding the
// fault config could silently contradict the image.
package main

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"
)

func main() {
	var (
		failRate = envFloat("FAIL_RATE", 0)
		latency  = time.Duration(envFloat("LATENCY_MS", 0)) * time.Millisecond
		addr     = ":" + env("PORT", "8080")
	)

	h := handler(failRate, latency)
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", h)
	mux.HandleFunc("/", h)

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("faultline listening on %s (FAIL_RATE=%.3f LATENCY_MS=%d)",
		addr, failRate, latency.Milliseconds())
	log.Fatal(srv.ListenAndServe())
}

// handler is the app's entire behaviour: wait, then fail with probability
// failRate. Both paths return the same thing, so a probe can hit /healthz or /
// and measure the same app.
func handler(failRate float64, latency time.Duration) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if latency > 0 {
			time.Sleep(latency)
		}
		if rand.Float64() < failRate {
			http.Error(w, "unhealthy\n", http.StatusInternalServerError)
			return
		}
		fmt.Fprintln(w, "ok")
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// envFloat reads a numeric env var, falling back on anything unparseable rather
// than refusing to start: a demo app that will not boot because of a typo in a
// manifest is worse than one that runs healthy.
func envFloat(key string, fallback float64) float64 {
	v, err := strconv.ParseFloat(env(key, ""), 64)
	if err != nil {
		return fallback
	}
	return v
}
