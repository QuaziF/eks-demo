#!/usr/bin/env bash
# Removes everything scripts/eks-up.sh created, in the order that does not orphan a load balancer.
#
#   1. Delete the EKS app from the Argo CD on the local kind cluster (its finalizer removes what it
#      deployed, including the Ingress; it must go first or self-heal recreates the Ingress), then
#      any Argo CD Applications inside EKS and any other Ingress or LoadBalancer Service, then WAIT until the ALB and its
#      security groups are gone. If the cluster were deleted first, the ALB would stay behind,
#      keep billing, and its network interfaces would block the VPC from being deleted.
#   2. terraform destroy (Helm releases, node group, cluster, IAM, VPC).
#   3. scripts/aws-status.sh must report ALL CLEAR. The exit code of this script is its result.
#
# The ECR repository (terraform/ecr) is kept on purpose, it costs cents. Remove it at the very
# end of the project with: terraform -chdir=terraform/ecr destroy
#
# Usage: scripts/teardown.sh [--all] [--skip-k8s]
#   (no option)  removes the AWS side only. The local kind cluster and the Argo CD on it keep
#                running, so you can carry on rehearsing locally or bring EKS up again later.
#   --all        AWS first, then, only if that ended ALL CLEAR, the local kind cluster too
#                (scripts/kind-down.sh). Docker Desktop and WSL are left running.
#   --skip-k8s   go straight to terraform destroy when the Kubernetes API cannot be reached. Delete
#                any ALB by hand first (EC2 console, Load Balancers), or it is left behind.
set -uo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

CLUSTER="eks-demo"
KUBECONFIG_FILE="${HOME}/.kube/eks-demo.config"
KIND_CONTEXT="${KIND_CONTEXT:-kind-demo}"
SKIP_K8S=0
ALL=0
for arg in "$@"; do
  case "${arg}" in
    --skip-k8s) SKIP_K8S=1 ;;
    --all) ALL=1 ;;
    *) echo "Unknown option: ${arg}. Options: --all, --skip-k8s (see the top of this script)." >&2; exit 2 ;;
  esac
done

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Not signed in to AWS. Run: aws login --remote --profile ${AWS_PROFILE}" >&2
  exit 1
fi

MYIP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
if [ -z "${MYIP}" ]; then
  echo "Could not detect your public IP." >&2
  exit 1
fi

start=${SECONDS}
K=(kubectl --kubeconfig "${KUBECONFIG_FILE}")

vpc_id() {
  local id
  id="$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${CLUSTER}" "Name=tag:project,Values=eks-demo" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
  if [ "${id}" != "None" ]; then echo "${id}"; fi
}

albs_in_vpc() {
  aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$1'].LoadBalancerName" --output text 2>/dev/null
}

controller_sgs() {
  aws ec2 describe-security-groups --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${CLUSTER}" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null
}

# wait_empty <label> <timeout seconds> <command printing what is left>
wait_empty() {
  local label="$1" timeout="$2" begin=${SECONDS} left
  shift 2
  while :; do
    left="$("$@")"
    if [ -z "${left}" ] || [ "${left}" = "None" ]; then
      echo "  ${label}: gone"
      return 0
    fi
    if [ $((SECONDS - begin)) -ge "${timeout}" ]; then
      echo "  ${label}: STILL THERE after ${timeout} s: ${left}" >&2
      return 1
    fi
    echo "  ${label}: waiting (${left})"
    sleep 10
  done
}

echo "== 1. Kubernetes: remove what the cluster put into AWS (ALB, security groups)"
if aws eks describe-cluster --name "${CLUSTER}" >/dev/null 2>&1; then
  if [ "${SKIP_K8S}" -eq 1 ]; then
    echo "  --skip-k8s given, not touching the cluster"
  else
    # The API is open to one IP only. If it changed since eks-up.sh, add the new one first.
    allowed="$(aws eks describe-cluster --name "${CLUSTER}" --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text)"
    if ! grep -qw "${MYIP}/32" <<<"${allowed}"; then
      echo "  your public IP changed (${MYIP}), updating the API allow list first (a few minutes)"
      (cd terraform/cluster && terraform apply -auto-approve -target=aws_eks_cluster.this -var "admin_cidr=${MYIP}/32") || true
    fi
    mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
    aws eks update-kubeconfig --name "${CLUSTER}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" \
      --kubeconfig "${KUBECONFIG_FILE}" --alias "${CLUSTER}" >/dev/null

    if "${K[@]}" get namespaces >/dev/null 2>&1; then
      # The app is managed by the Argo CD on the local kind cluster (scripts/eks-deploy.sh). Delete it
      # THERE first: with selfHeal on, that Argo CD would recreate any Ingress deleted by hand below.
      HUB=(env -u KUBECONFIG kubectl --context "${KIND_CONTEXT}")
      if "${HUB[@]}" -n argocd get applications.argoproj.io >/dev/null 2>&1; then
        echo "  deleting the EKS app from the Argo CD on kind (cascades to the Ingress, so the ALB goes)"
        if ! "${HUB[@]}" -n argocd delete application demo-app-eks --ignore-not-found --wait=true --timeout=300s; then
          echo "  delete timed out: removing its finalizer so it cannot recreate anything, Ingress is deleted below" >&2
          "${HUB[@]}" -n argocd patch application demo-app-eks --type merge -p '{"metadata":{"finalizers":null}}' || true
          "${HUB[@]}" -n argocd delete application demo-app-eks --ignore-not-found --wait=false || true
        fi
        echo "  removing the eks-demo cluster from the Argo CD on kind"
        "${HUB[@]}" -n argocd delete secret cluster-eks-demo --ignore-not-found || true
      else
        echo "  Argo CD on kind is not reachable (context ${KIND_CONTEXT}), nothing there can recreate resources"
      fi
      # Only exists when the optional Argo CD inside EKS was installed (install_argocd).
      if "${K[@]}" get crd applications.argoproj.io >/dev/null 2>&1; then
        echo "  deleting Argo CD applications inside EKS (cascades to everything they deployed)"
        "${K[@]}" delete applications.argoproj.io --all --all-namespaces --wait=true --timeout=300s || true
      fi
      echo "  deleting any other Ingress"
      "${K[@]}" delete ingress --all --all-namespaces --wait=true --timeout=180s || true
      echo "  deleting any LoadBalancer Services"
      "${K[@]}" get svc --all-namespaces \
        -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' |
        while read -r ns name; do
          [ -n "${name}" ] && "${K[@]}" -n "${ns}" delete svc "${name}" --wait=true --timeout=180s || true
        done
    else
      echo "  CANNOT REACH the Kubernetes API. Stopping so no ALB is left behind." >&2
      echo "  Check your sign-in and network, or re-run with --skip-k8s after deleting any ALB by hand." >&2
      exit 1
    fi

    vpc="$(vpc_id)"
    if [ -n "${vpc}" ]; then
      wait_empty "load balancers in ${vpc}" 600 albs_in_vpc "${vpc}" || { echo "Not destroying: an ALB is still there." >&2; exit 1; }
    fi
    wait_empty "controller security groups" 180 controller_sgs || echo "  continuing, destroy will report it if it blocks the VPC" >&2
  fi
else
  echo "  no EKS cluster named ${CLUSTER}, skipping the cluster side"
  # If it was destroyed some other way, the hub on kind still lists the dead cluster and its app.
  HUB=(env -u KUBECONFIG kubectl --context "${KIND_CONTEXT}")
  if "${HUB[@]}" -n argocd get application demo-app-eks >/dev/null 2>&1; then
    echo "  removing the leftover demo-app-eks and eks-demo entries from the Argo CD on kind"
    "${HUB[@]}" -n argocd patch application demo-app-eks --type merge -p '{"metadata":{"finalizers":null}}' || true
    "${HUB[@]}" -n argocd delete application demo-app-eks --ignore-not-found --wait=false || true
  fi
  "${HUB[@]}" -n argocd delete secret cluster-eks-demo --ignore-not-found >/dev/null 2>&1 || true
fi

echo "== 2. terraform destroy"
(cd terraform/cluster && terraform init -input=false >/dev/null && terraform destroy -auto-approve -var "admin_cidr=${MYIP}/32")
destroy_rc=$?

echo "== 3. what is still running"
scripts/aws-status.sh
status_rc=$?

echo
echo "teardown took $(( (SECONDS - start) / 60 )) min (terraform destroy exit ${destroy_rc}, status check exit ${status_rc})"
if [ "${destroy_rc}" -ne 0 ] || [ "${status_rc}" -ne 0 ]; then
  if [ "${ALL}" -eq 1 ]; then echo "AWS is not clean, so the local kind cluster was NOT removed (you may need it to retry)." >&2; fi
  exit 1
fi

if [ "${ALL}" -eq 1 ]; then
  echo "== 4. local: removing the kind cluster (--all)"
  scripts/kind-down.sh --force
else
  echo "The local kind cluster and its Argo CD were left running. Add --all to remove them as well."
fi
