#!/usr/bin/env bash
# Deploys the demo app onto the EKS cluster. The Argo CD that manages it is the one on the local
# kind cluster (the hub): this script registers EKS there as a second destination, applies
# argocd/application-eks.yaml (app "demo-app-eks", destination "eks-demo") with the inbound-cidrs
# placeholder replaced by this machine's public IP (the ALB only accepts that address), waits for
# Synced and Healthy, and prints the ALB URL.
#
# Needs: the EKS cluster up (scripts/eks-up.sh) and the kind side up (scripts/rehearsal-up.sh).
# Safe to run again: it is also how you refresh the allowed IP after your home IP changes.
# Look at it in the UI with scripts/argocd-ui.sh (the kind Argo CD shows both clusters).
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

EKS_KUBECONFIG="${EKS_KUBECONFIG:-${HOME}/.kube/eks-demo.config}"
KIND_CONTEXT="${KIND_CONTEXT:-kind-demo}"
EKS=(kubectl --kubeconfig "${EKS_KUBECONFIG}")
HUB=(env -u KUBECONFIG kubectl --context "${KIND_CONTEXT}")

scripts/argocd-register-eks.sh

MYIP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "The ALB will accept traffic only from ${MYIP}/32 (this machine's public IP)."

sed "s#203.0.113.10/32#${MYIP}/32#" argocd/application-eks.yaml | "${HUB[@]}" apply -f -

echo "Waiting for Argo CD (on kind) to sync EKS and the app to become Healthy ..."
"${HUB[@]}" -n argocd wait application/demo-app-eks --for=jsonpath='{.status.sync.status}'=Synced --timeout=240s
"${HUB[@]}" -n argocd wait application/demo-app-eks --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s

echo "Waiting for the load balancer controller to publish the ALB address ..."
host=""
for _ in $(seq 1 40); do
  host="$("${EKS[@]}" -n demo get ingress demo-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "${host}" ] && break
  sleep 10
done
if [ -z "${host}" ]; then
  echo "No ALB address after ~7 minutes. Check: kubectl --kubeconfig ${EKS_KUBECONFIG} -n demo describe ingress demo-app" >&2
  exit 1
fi

echo "ALB: http://${host}"
echo "The ALB costs money while it exists; scripts/teardown.sh removes it."
