#!/usr/bin/env bash
# Opens the Argo CD UI at http://localhost:8081 through a port-forward (Ctrl+C to stop).
# Login: user admin, password from scripts/argocd-password.sh
export PATH="${HOME}/.local/bin:${PATH}"
echo "Argo CD UI: http://localhost:8081   (user: admin, password: scripts/argocd-password.sh)"
exec kubectl -n argocd port-forward svc/argocd-server 8081:80
