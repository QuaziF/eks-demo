#!/usr/bin/env bash
# Runs the k6 ramp and samples the HPA every 10s into a timeline file, then keeps sampling
# through a cooldown so scale-down is captured too. For rehearsal; for the recording, watch
# `kubectl get hpa -w` in its own pane instead.
# Usage: BASE_URL=http://localhost:8080 COOLDOWN=180 scripts/loadtest.sh
set -uo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

BASE_URL="${BASE_URL:-http://localhost:8080}"
COOLDOWN="${COOLDOWN:-180}"
LOG="${LOG:-/tmp/hpa-timeline.log}"
: > "${LOG}"

sample() {
  while true; do
    hpa="$(kubectl -n demo get hpa demo-app --no-headers 2>/dev/null | awk '{print "cpu=" $4 " replicas=" $7}')"
    ready="$(kubectl -n demo get deploy demo-app --no-headers 2>/dev/null | awk '{print $2}')"
    echo "$(date +%T) ${hpa} ready=${ready}" >> "${LOG}"
    sleep 10
  done
}
sample &
SAMPLER=$!
trap 'kill ${SAMPLER} 2>/dev/null' EXIT

BASE_URL="${BASE_URL}" k6 run loadtest/k6.js
echo "$(date +%T) load finished, cooling down for ${COOLDOWN}s" >> "${LOG}"
sleep "${COOLDOWN}"
echo "$(date +%T) done" >> "${LOG}"
