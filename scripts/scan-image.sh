#!/usr/bin/env bash
# Scans a local image for known HIGH and CRITICAL vulnerabilities with Trivy and prints a short
# summary: one table row per component with a count, then the totals. (Trivy also prints a
# per-package table with a row for every CVE; for a 1.4 GB image that is hundreds of lines, so this
# script keeps only the summary and the totals. Run Trivy by hand for the full list.)
#
# Trivy runs as a container, so nothing needs installing: it reads the image through the Docker
# socket and keeps its vulnerability database in the Docker volume "trivy-cache", so only the first
# scan downloads it (about 2 minutes). The Trivy version is pinned, like everything else in this
# repo. A big image is slow to scan: the 1.4 GB naive image takes about a minute even when warm,
# the 15.7 MB production image takes about two seconds.
#
# Usage: scripts/scan-image.sh <image>      e.g. scripts/scan-image.sh demo-app:0.1.1
set -euo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.76.2}"
IMAGE="${1:?usage: scripts/scan-image.sh <image>}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "${IMAGE} is not in the local Docker image store" >&2
  exit 1
fi

out="$(docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache/ \
  "aquasec/trivy:${TRIVY_VERSION}" image \
  --quiet --scanners vuln --severity HIGH,CRITICAL --format table --report summary \
  "${IMAGE}")"

# Everything up to and including the summary's legend, then only the "Total:" lines.
awk 'BEGIN { p = 1 } p { print } /Clean \(no security findings detected\)/ { p = 0 }' <<<"${out}"
totals="$(grep -E '^Total:' <<<"${out}" || true)"
if [ -n "${totals}" ]; then
  echo
  echo "${totals}"
else
  echo
  echo "No HIGH or CRITICAL vulnerabilities found."
fi
