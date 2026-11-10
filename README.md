# eks-demo

Demo project for the "Master Containerization and Orchestration" goal: a small Go service, built as a hardened Docker image, deployed to Kubernetes with GitOps (Argo CD), and autoscaled under load. The same manifests run on a local kind cluster (free rehearsal) and on EKS (the recording).

See [PLAN.md](PLAN.md) for the plan, costs, storyboard and decisions, and [docs/recording/](docs/recording/README.md) for the reading script and screen guide for each chapter of the recording.

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
| `docs/recording/` | Reading script and screen guide per chapter: narration, commands, screen layout, how to cut long waits. Start with its [README](docs/recording/README.md) |
| `scripts/` | Everything below. Recording helpers: `rec-prep.sh` (pre-flight: `ch1`, `ch1x` or `eks`), `scan-image.sh` (Trivy summary), `traffic.sh` (live request stream), `release.sh` (one-command release) |

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

After `rehearsal-up.sh`, a deploy is a git push to `main`: Argo CD polls every 30 s and syncs `k8s/overlays/kind`. Use `kind-deploy.sh` only to skip Argo. A new image version needs `scripts/kind-load.sh <version>` first, because kind nodes cannot pull local images. `scripts/release.sh` does all of that in one command (next section).

### Releasing a new version

Argo CD deploys what git says and never builds anything, so changing the app code alone deploys nothing: a release is a commit that changes `newTag` in an overlay (`k8s/overlays/kind`, `k8s/overlays/eks`). `scripts/release.sh` does the steps a CI pipeline would:

```bash
scripts/release.sh 0.2.0              # build, load into kind, push to ECR, bump newTag in both overlays, commit, push, wait for Argo CD
scripts/release.sh 0.2.0 --kind-only  # local only, no AWS needed
scripts/release.sh 0.2.0 --eks-only   # EKS only, no kind needed
scripts/release.sh 0.2.0 --dry-run    # run the checks, show the plan, change nothing
```

Commit your app change first. The script refuses to build from uncommitted `app/` changes (the image must map to a commit), from a branch other than the one Argo CD watches, from a branch that is behind origin, and with the mutable tag `latest` (ECR tags are immutable, so every release needs a new tag). It commits only the overlay file(s), so other local edits, such as the IP that `eks-deploy.sh` writes into `argocd/application-eks.yaml`, stay out. Afterwards it waits (up to 4 min) until the Argo CD app on the hub is Synced and Healthy at the pushed commit; an app that is not deployed (EKS is down) is skipped and picks the tag up when it is deployed. Roll back with a `git revert` of the release commit and a push. `--no-push` stops after the commit.

In a team this would be CI (build, scan, push an immutable tag, commit the bump to a config repo) or an image updater such as Argo CD Image Updater writing the tag back to git.

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

If a watch against EKS ends after about a minute with `unable to decode an event from the watch stream: http2: client connection lost`, run `export DISABLE_HTTP2=1` first. From my WSL2 machine the EKS API endpoint never answers kubectl's HTTP/2 keepalive ping (a trace shows the PING sent after 30 s idle and no reply, so kubectl closes the connection 15 s later); plain requests are fine and a watch with HTTP/2 off ran 10 minutes without a drop. It only affects long-lived watches: `get -w` for sure, and probably `kubectl wait` or `rollout status` when nothing changes for a minute (not tested). It is harmless against kind. I did not find out whether the cause is on the AWS side or on the network path.

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
