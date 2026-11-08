#!/usr/bin/env bash
# Registers the EKS cluster as a deployment target of the Argo CD that runs on the local kind
# cluster, so one Argo CD UI shows both clusters ("in-cluster" is kind, "eks-demo" is EKS).
# It does what `argocd cluster add` does, without needing the argocd CLI:
#   1. In EKS: a ServiceAccount "argocd-manager" with full rights and a long-lived token.
#   2. In kind: a Secret in the argocd namespace, labelled as a cluster, holding that token, the
#      EKS API address and its CA. The token goes from one cluster to the other and is never
#      printed or written to a file.
# The EKS API only accepts your public IP. Kind reaches it through your home connection, so that
# works from here. Run it again after every scripts/eks-up.sh (a new cluster has a new address and
# token); scripts/eks-deploy.sh does that for you. It is safe to run repeatedly.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

EKS_KUBECONFIG="${EKS_KUBECONFIG:-${HOME}/.kube/eks-demo.config}"
KIND_CONTEXT="${KIND_CONTEXT:-kind-demo}"
EKS=(kubectl --kubeconfig "${EKS_KUBECONFIG}")
# env -u: a KUBECONFIG exported for EKS in your shell must not hide the kind context.
HUB=(env -u KUBECONFIG kubectl --context "${KIND_CONTEXT}")

if [ "$("${EKS[@]}" config current-context 2>/dev/null)" != "eks-demo" ]; then
  echo "No eks-demo kubeconfig at ${EKS_KUBECONFIG}. Is the cluster up (scripts/eks-up.sh)?" >&2
  exit 1
fi
if ! "${HUB[@]}" -n argocd get statefulset argocd-application-controller >/dev/null 2>&1; then
  echo "Argo CD is not running on kind (context ${KIND_CONTEXT}). Start it: scripts/rehearsal-up.sh" >&2
  exit 1
fi

echo "Creating the argocd-manager account in EKS ..."
"${EKS[@]}" apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
  - nonResourceURLs: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

token_b64=""
for _ in $(seq 1 30); do
  token_b64="$("${EKS[@]}" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
  [ -n "${token_b64}" ] && break
  sleep 2
done
if [ -z "${token_b64}" ]; then
  echo "The service account token was not issued after 60 s." >&2
  exit 1
fi

SERVER="$("${EKS[@]}" config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')"
CA="$("${EKS[@]}" config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
TOKEN="$(printf '%s' "${token_b64}" | base64 -d)"

echo "Registering ${SERVER} in the Argo CD on kind as 'eks-demo' ..."
# A heredoc keeps the token out of the process list and the terminal.
cat <<EOF | "${HUB[@]}" apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: cluster-eks-demo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: eks-demo
  server: ${SERVER}
  config: '{"bearerToken":"${TOKEN}","tlsClientConfig":{"insecure":false,"caData":"${CA}"}}'
EOF

echo "Done. Argo CD on kind now has two destinations: in-cluster (kind) and eks-demo (${SERVER})."
