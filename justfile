# faultline — task automation
# Run `just` with no arguments to list recipes.

image := env_var_or_default("FAULTLINE_IMAGE", "faultline:dev")
port := env_var_or_default("FAULTLINE_PORT", "8080")

default:
    @just --list

# Compile the binary into ./bin/faultline
build:
    go build -o bin/faultline .

# Format check and static analysis
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    unformatted="$(gofmt -l .)"
    if [ -n "$unformatted" ]; then
        echo "These files need gofmt:"
        echo "$unformatted"
        exit 1
    fi
    go vet ./...

# Run all the tests
test:
    go test ./... -count=1

# Everything CI runs, locally
check: lint test image

# Format all Go sources
fmt:
    go fmt ./...

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

# Tag and push a release, which is what publishes the images
release bump="patch":
    #!/usr/bin/env bash
    set -euo pipefail

    branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$branch" = main ] || { echo "release from main, not $branch" >&2; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }
    git fetch --tags --quiet

    latest=$(git tag --list 'v*' --sort=-v:refname | head -1)
    [ -n "$latest" ] || latest="v0.0.0"
    IFS=. read -r major minor patch <<< "${latest#v}"
    case "{{bump}}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "bump must be patch, minor or major" >&2; exit 1 ;;
    esac
    next="v${major}.${minor}.${patch}"

    echo "$latest → $next"
    git tag -a "$next" -m "faultline $next"
    git push origin "$next"
    echo "pushed $next — the publish workflow will build every profile tag"

clean:
    rm -rf bin coverage.out coverage.html
