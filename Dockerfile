# syntax=docker/dockerfile:1
#
# FAIL_RATE and LATENCY_MS are build args that become defaults in the image, and
# stay overridable at run time. That is what lets one Dockerfile produce both
# the plain image, which you configure with `docker run -e FAIL_RATE=0.2`, and
# the profile tags, whose behaviour is baked in so the tag alone says what the
# workload does. See README.md for the profile table.

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/faultline .

FROM scratch
ARG FAIL_RATE=0
ARG LATENCY_MS=0
ENV FAIL_RATE=${FAIL_RATE} \
    LATENCY_MS=${LATENCY_MS} \
    PORT=8080
COPY --from=build /out/faultline /faultline
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/faultline"]
