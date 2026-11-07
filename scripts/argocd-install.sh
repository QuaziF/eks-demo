#!/usr/bin/env bash
# Installs Argo CD on the kind cluster with Helm and applies the demo Application, which then
# deploys k8s/overlays/kind from GitHub. Safe to re-run.
# Prereq: the kind cluster is up (scripts/kind-up.sh) and the demo image is loaded (scripts/kind-load.sh).
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.14.0}" # Argo CD v3.6.1

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version "${ARGOCD_CHART_VERSION}" \
  --namespace argocd --create-namespace -f argocd/values.yaml --wait --timeout 5m

kubectl apply -f argocd/application-kind.yaml

echo "waiting for the demo-app Application to sync from git..."
sync="" health=""
for _ in $(seq 1 36); do
  sync="$(kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get application demo-app -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  echo "  sync=${sync:-?} health=${health:-?}"
  if [ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ]; then break; fi
  sleep 5
done

kubectl -n argocd get pods
kubectl -n argocd get application demo-app
kubectl -n demo get deploy,hpa,pods
[ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ]
