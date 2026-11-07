#!/usr/bin/env bash
# Creates the local rehearsal cluster and installs metrics-server (needed by the HPA).
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

if kind get clusters 2>/dev/null | grep -qx demo; then
  echo "kind cluster 'demo' already exists"
else
  kind create cluster --config kind/kind-config.yaml
fi

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update metrics-server >/dev/null
# kind kubelets use self-signed certs, so metrics-server needs --kubelet-insecure-tls here.
# Do NOT carry that flag over to EKS.
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version 3.14.0 --namespace kube-system \
  --set 'args[0]=--kubelet-insecure-tls' --wait

kubectl get nodes -o wide
