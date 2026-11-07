#!/usr/bin/env bash
# Prints the initial Argo CD admin password (generated at install time, stored in a Secret).
export PATH="${HOME}/.local/bin:${PATH}"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
