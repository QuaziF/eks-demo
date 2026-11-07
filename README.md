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
