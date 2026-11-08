#!/usr/bin/env bash
# Creates the EKS cluster and its add-ons with Terraform (terraform/cluster).
#
#   THIS COSTS MONEY WHILE IT EXISTS: about 0.32 USD per hour (EKS control plane 0.10, two
#   c7i-flex.large nodes, public IPs, plus the ALB once the app is deployed). Create takes about
#   15 to 20 minutes. Tear down with scripts/teardown.sh when the session ends.
#
# Usage: scripts/eks-up.sh [--yes]     (--yes skips Terraform's confirmation prompt)
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

CLUSTER="eks-demo"
KUBECONFIG_FILE="${HOME}/.kube/eks-demo.config"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Not signed in to AWS. Run: aws login --remote --profile ${AWS_PROFILE}" >&2
  exit 1
fi

# Only this address may reach the Kubernetes API from the internet.
MYIP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
if [ -z "${MYIP}" ]; then
  echo "Could not detect your public IP." >&2
  exit 1
fi

cat <<EOF

About to create EKS cluster "${CLUSTER}" in ${AWS_REGION} (account $(aws sts get-caller-identity --query Account --output text)).
  cost while it exists: about 0.32 USD per hour (about 7.80 USD per day if forgotten)
  Kubernetes API allowed from: ${MYIP}/32
  tear down with: scripts/teardown.sh

EOF

approve=()
if [ "${1:-}" = "--yes" ]; then approve=(-auto-approve); fi

start=${SECONDS}
cd terraform/cluster
terraform init -input=false
terraform apply "${approve[@]}" -var "admin_cidr=${MYIP}/32"
cd ../..

# A separate kubeconfig file, so kubectl keeps pointing at kind unless you ask for EKS.
mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
aws eks update-kubeconfig --name "${CLUSTER}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" \
  --kubeconfig "${KUBECONFIG_FILE}" --alias "${CLUSTER}" >/dev/null

echo
echo "cluster is up after $(( (SECONDS - start) / 60 )) min"
kubectl --kubeconfig "${KUBECONFIG_FILE}" get nodes -o wide
kubectl --kubeconfig "${KUBECONFIG_FILE}" get pods -A

cat <<EOF

The cost clock is running. To use the cluster in this shell:
  export KUBECONFIG=${KUBECONFIG_FILE}
Deploy the app:  scripts/eks-deploy.sh   (the Argo CD on kind manages EKS; UI: scripts/argocd-ui.sh)
Tear down:       scripts/teardown.sh     (AWS only, kind stays up; --all removes kind as well)
An Argo CD inside EKS is optional and off by default: TF_VAR_install_argocd=true scripts/eks-up.sh
EOF
