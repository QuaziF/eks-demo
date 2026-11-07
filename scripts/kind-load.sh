#!/usr/bin/env bash
# Makes the demo image available inside the kind nodes, building it first if Docker does not have it.
# Usage: scripts/kind-load.sh [version]   (default 0.1.0; must match the tag in k8s/overlays/kind)
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
if ! docker image inspect "demo-app:${VERSION}" >/dev/null 2>&1; then
  echo "demo-app:${VERSION} is not in Docker, building it"
  scripts/build-local.sh "${VERSION}"
fi
kind load docker-image "demo-app:${VERSION}" --name demo
