#!/usr/bin/env bash
# Deletes the local kind cluster (and with it the Argo CD on it and everything it deployed locally).
# Docker Desktop and WSL are left running.
#
# The Argo CD on kind is what removes the EKS app and its ALB cleanly (scripts/teardown.sh), so this
# refuses to run while the EKS cluster still exists. Run scripts/teardown.sh first (add --all to
# have it call this for you), or pass --force if you know what you are doing.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}" AWS_PAGER=""

if [ "${1:-}" != "--force" ] && command -v aws >/dev/null 2>&1; then
  rc=0
  out="$(timeout 20 aws eks describe-cluster --name eks-demo 2>&1)" || rc=$?
  if [ "${rc}" -eq 0 ]; then
    echo "The EKS cluster eks-demo is still up and costs money. Removing kind first means teardown can no" >&2
    echo "longer use the hub Argo CD to delete the ALB. Run scripts/teardown.sh first, or re-run with --force." >&2
    exit 1
  elif ! grep -q ResourceNotFoundException <<<"${out}"; then
    echo "note: could not check whether the EKS cluster exists (signed out?), continuing: ${out%%$'\n'*}" >&2
  fi
fi

kind delete cluster --name demo
