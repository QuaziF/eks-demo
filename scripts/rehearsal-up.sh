#!/usr/bin/env bash
# One command for the local rehearsal environment: kind cluster with metrics-server, the demo
# image loaded into the nodes, Argo CD installed, and the demo app synced from GitHub.
# Needs Docker Desktop running. Takes a few minutes the first time.
# Usage: scripts/rehearsal-up.sh [version]   (default 0.1.0)
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/kind-up.sh
scripts/kind-load.sh "${1:-0.1.0}"
scripts/argocd-install.sh

cat <<'EOF'

Ready.
  app:       http://localhost:8080/
  Argo CD:   scripts/argocd-ui.sh        (then http://localhost:8081, user admin, password: scripts/argocd-password.sh)
  tear down: scripts/kind-down.sh
EOF
