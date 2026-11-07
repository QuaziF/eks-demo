#!/usr/bin/env bash
# Chapter 1 crib sheet: Docker CLI debugging drills against the demo image.
# Each drill prints what it is doing so it can be narrated while it runs.
# Usage: scripts/docker-drills.sh [version]   (default 0.1.0)
set -uo pipefail
IMG="demo-app:${1:-0.1.0}"
PORT=18080

cleanup() { docker rm -f drill-ok drill-missing-env drill-oom >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "### 0. Image facts"
docker images demo-app --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'
echo "user:   $(docker inspect --format '{{.Config.User}}' "${IMG}")"
echo "labels: $(docker inspect --format '{{json .Config.Labels}}' "${IMG}")"
echo "layers:"; docker history --format 'table {{.Size}}\t{{.CreatedBy}}' "${IMG}" | cut -c1-110

echo
echo "### 1. Happy path: run, probe, read logs, check HEALTHCHECK"
docker run -d --name drill-ok -p ${PORT}:8080 -e APP_MODE=demo -e APP_GREETING="hello from docker" \
  --read-only --cap-drop ALL "${IMG}" >/dev/null
sleep 2
curl -s localhost:${PORT}/; echo
curl -s localhost:${PORT}/version; echo
echo "health after start period: waiting 15s..."
sleep 15
echo "health: $(docker inspect --format '{{.State.Health.Status}}' drill-ok)"
docker logs drill-ok 2>&1 | tail -3

echo
echo "### 2. Container exits immediately: missing required env var"
docker run --name drill-missing-env "${IMG}"
echo "exit code: $(docker inspect --format '{{.State.ExitCode}}' drill-missing-env)  (docker logs shows the reason above)"

echo
echo "### 3. Memory limit: OOM kill"
docker run -d --name drill-oom -p $((PORT+1)):8080 -e APP_MODE=demo --memory 64m --memory-swap 64m "${IMG}" >/dev/null
sleep 2
echo "asking the app to hold 200 MB inside a 64 MB limit..."
curl -s -m 5 "localhost:$((PORT+1))/alloc?mb=200" || echo "(connection dropped: process was killed)"
sleep 2
echo "OOMKilled: $(docker inspect --format '{{.State.OOMKilled}}' drill-oom)  exit code: $(docker inspect --format '{{.State.ExitCode}}' drill-oom)"

echo
echo "### 4. Misc checks"
echo "whoami inside (no shell in distroless, so inspect instead): $(docker inspect --format '{{.Config.User}}' drill-ok)"
docker stats --no-stream drill-ok 2>/dev/null | cat
