#!/usr/bin/env bash
# Loads the image into kind and applies the kind overlay. Used for local rehearsal only;
# on EKS, Argo CD does the deploy from git.
# Usage: scripts/kind-deploy.sh [version]   (default 0.1.0; must match overlays/kind tag)
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
kind load docker-image "demo-app:${VERSION}" --name demo
kubectl apply -k k8s/overlays/kind
kubectl -n demo rollout status deploy/demo-app --timeout=120s
kubectl -n demo get deploy,hpa,pods,svc
