#!/usr/bin/env bash
# Builds the naive and the multi-stage image and prints a size comparison.
# Usage: scripts/build-local.sh [version]   (default 0.1.0)
set -euo pipefail
cd "$(dirname "$0")/../app"

VERSION="${1:-0.1.0}"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo none)"

docker build -f Dockerfile.naive -t demo-app:naive .
docker build -f Dockerfile \
  --build-arg VERSION="${VERSION}" --build-arg COMMIT="${COMMIT}" \
  -t "demo-app:${VERSION}" .

echo
docker images demo-app --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'
