#!/usr/bin/env bash
# A live, readable stream of requests for the screen: one line per request with the time, the HTTP
# status (green 200, red anything else), the app version and the pod and node that answered.
# During a rolling update you watch the version flip from one value to the next with no red line;
# during a break-fix drill you watch which pods keep answering. Ctrl+C prints the totals.
#
# Usage: scripts/traffic.sh <base-url> [seconds-between-requests]
#   scripts/traffic.sh http://localhost:8080                  (kind)
#   scripts/traffic.sh "http://$ALB" 0.5                      (EKS, ALB address from eks-deploy.sh)
set -u
URL="${1:?usage: scripts/traffic.sh <base-url> [seconds-between-requests]}"
INTERVAL="${2:-0.5}"
total=0
bad=0
trap 'echo; echo "requests=${total}  not 200=${bad}"; exit 0' INT TERM

while :; do
  out="$(curl -s -m 3 -w '\n%{http_code}' "${URL}/" 2>/dev/null)"
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  version="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' <<<"${body}")"
  pod="$(sed -n 's/.*"pod":"\([^"]*\)".*/\1/p' <<<"${body}")"
  node="$(sed -n 's/.*"node":"\([^"]*\)".*/\1/p' <<<"${body}")"
  total=$((total + 1))
  if [ "${code}" = 200 ]; then color=32; else color=31; bad=$((bad + 1)); fi
  printf '%s \033[%sm%s\033[0m  %-8s %-34s %s\n' "$(date +%T)" "${color}" "${code}" "${version:--}" "${pod:--}" "${node:--}"
  sleep "${INTERVAL}"
done
