# faultline — task automation
# Run `just` with no arguments to list recipes.

image := env_var_or_default("FAULTLINE_IMAGE", "faultline:dev")
port := env_var_or_default("FAULTLINE_PORT", "8080")

default:
    @just --list

# Compile the binary into ./bin/faultline
build:
    go build -o bin/faultline .

# Run the test suite
test:
    go test ./... -count=1

# Static analysis
vet:
    go vet ./...

# Format all Go sources
fmt:
    go fmt ./...

# Everything CI runs, locally
check: fmt vet test image

# Build the container image locally
image fail_rate="0.0" latency_ms="0":
    docker build -t {{image}} --build-arg FAIL_RATE={{fail_rate}} --build-arg LATENCY_MS={{latency_ms}} .

# Run the server locally. `just serve 0.35 15` fails a third of requests.
serve fail_rate="0.0" latency_ms="0":
    FAIL_RATE={{fail_rate}} LATENCY_MS={{latency_ms}} PORT={{port}} go run .

# Hit the server 20 times and count the failures
probe path="/healthz":
    #!/usr/bin/env bash
    set -euo pipefail
    failures=0
    for _ in $(seq 20); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:{{port}}{{path}}")
        [ "$code" = 200 ] || failures=$((failures + 1))
    done
    echo "$failures/20 failed"

clean:
    rm -rf bin coverage.out coverage.html
