# eks-demo

Demo project for the "Master Containerization and Orchestration" goal: a small Go service, built as a hardened Docker image, deployed to Kubernetes with GitOps (Argo CD), and autoscaled under load. The same manifests run on a local kind cluster (free rehearsal) and on EKS (the recording).

See [PLAN.md](PLAN.md) for the plan, costs, storyboard and decisions.

## Layout

| Path | What it is |
|---|---|
| `app/` | Go service, `Dockerfile.naive` (the "before") and `Dockerfile` (multi-stage, distroless, non-root) |
| `k8s/base/` | Deployment, Service, HPA, PDB, ConfigMap generator, Secret (fake value) |
| `k8s/overlays/kind/` | Local: image from the local daemon, Service as NodePort on localhost:8080 |
| `k8s/overlays/eks/` | EKS: ECR image, ALB Ingress (needs the AWS Load Balancer Controller) |
| `kind/` | kind cluster config (3 nodes, Kubernetes 1.36) |
| `argocd/` | Argo CD Helm values and the demo Application (watches this repo) |
| `terraform/` | `ecr/` (the registry, stays up) and `cluster/` (VPC, EKS, add-ons, costs money while it exists). See [terraform/README.md](terraform/README.md) |
| `loadtest/` | k6 ramp script |
| `scripts/` | Everything below |

## Local rehearsal (WSL Ubuntu, Docker Desktop running)

Run these inside WSL, from this folder.

```bash
scripts/setup-wsl-tools.sh        # once: kind, kubectl, helm, k9s, k6, gh, terraform, aws into ~/.local/bin
scripts/verify.sh                 # manifests render, Go code formats and vets
scripts/build-local.sh 0.1.0      # naive vs multi-stage image, prints sizes
scripts/docker-drills.sh          # Chapter 1 drills: exit code, healthcheck, OOM kill
scripts/kind-up.sh                # kind cluster + metrics-server
scripts/kind-deploy.sh 0.1.0      # load image into kind, apply overlays/kind
curl localhost:8080/              # who answered
scripts/loadtest.sh               # k6 ramp, HPA timeline sampled to /tmp/hpa-timeline.log
scripts/kind-down.sh              # delete the cluster
```

### With Argo CD (what the recording uses)

```bash
scripts/rehearsal-up.sh           # kind + metrics-server + image + Argo CD + the demo app, synced from GitHub
scripts/argocd-ui.sh              # http://localhost:8081, user admin (leave running in its own pane)
scripts/argocd-password.sh        # prints the initial admin password
scripts/kind-down.sh              # delete the cluster when done (refuses while the EKS cluster is up)
scripts/aws-status.sh             # AWS: Free plan credits left, anything billable still running
```

After `rehearsal-up.sh`, a deploy is a git push to `main`: Argo CD polls every 30 s and syncs `k8s/overlays/kind`. Use `kind-deploy.sh` only to skip Argo. A new image version needs `scripts/kind-load.sh <version>` first, because kind nodes cannot pull local images.

### On AWS (costs money while the cluster exists)

```bash
aws login --remote --profile eks-demo   # about 12 hours per login
scripts/ecr-push.sh 0.1.0               # image into ECR (the registry stack stays up between sessions)
scripts/eks-up.sh                       # about 0.32 USD per hour from here
scripts/eks-deploy.sh                   # registers EKS in the Argo CD on kind, deploys demo-app-eks, prints the ALB URL
scripts/argocd-ui.sh                    # one UI for both clusters (kind is "in-cluster", EKS is "eks-demo")
scripts/teardown.sh                     # always, when the session ends: AWS only, kind and its Argo CD keep running
scripts/teardown.sh --all               # AWS first, then the local kind cluster too
scripts/aws-status.sh                   # credits left, ALL CLEAR or what is still running
```

Useful panes while the load test runs:

```bash
kubectl -n demo get hpa -w
kubectl -n demo get pods -w
k9s -n demo
```

## App endpoints

| Path | Purpose |
|---|---|
| `/` | JSON with pod, node, version: shows load spreading |
| `/healthz`, `/readyz` | liveness and readiness probes |
| `POST /toggle-ready` | flip readiness at runtime |
| `/work?ms=N` | burn CPU for N ms (HPA driver) |
| `/alloc?mb=N`, `/free` | hold or release memory (OOM drills) |
| `/config`, `/secret-check`, `/version` | show ConfigMap values, Secret presence, build info |

Set `APP_MODE` or the container exits with code 1 (deliberate, for the crash drills).
