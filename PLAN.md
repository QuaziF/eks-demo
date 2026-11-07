# Containerization and Orchestration Demo: Plan

Goal: "Master Containerization and Orchestration" (Docker image engineering, container debugging, Kubernetes deploy and operations). Deliverable is a screen-recorded demo. Secondary benefit: AWS competency, via EKS.

Plan written 2026-11-06. Prices and facts below were read from AWS pages and a few third-party sources on that date. Items I could not verify are listed in section 10. Re-check anything money-related before you click create.

---

## 1. Decisions in one screen

| Question | Recommendation |
|---|---|
| Which AWS account? | Your existing personal account. Correction 2026-11-07: it is on the Free plan with the full 100 USD credits unspent, plan ends 2027-05-06 (`aws freetier get-account-plan-state`). Do not open a second account for free credits (section 2). |
| Realistic total cost | About 8 to 13 USD for the whole project if the cluster only runs during work sessions. About 0.32 USD per hour while up (nodes are c7i-flex.large, see Nodes). It comes out of the 100 USD Free plan credits, if EKS charges are creditable (unconfirmed, check with `scripts/aws-status.sh` after the first run). |
| Biggest cost risk | Forgetting to tear down (about 233 USD per month; on the Free plan that burns the credits, and when they run out the account closes), or running a Kubernetes version in extended support (control plane goes 0.10 to 0.60 USD per hour). |
| Region | us-east-1 (decided). The EKS control plane is one flat price in every region, and t3.medium is the same price in us-east-1, us-east-2 and us-west-2 (from memory, not compared side by side), so cost does not separate them. us-east-1 has the most capacity and add-on support. |
| Cluster build tool | Terraform (decided). terraform-aws-modules for VPC and EKS, Helm releases for the add-ons, state kept locally for this one-person demo. |
| Video length | 10 to 15 minutes (decided). The storyboard in section 5 is cut to fit. |
| Teardown | `scripts/teardown.sh`: delete the Argo CD Applications and wait for the ALB to disappear, then `terraform destroy`. `terraform destroy` alone is not enough, because the ALB is created by the in-cluster controller and is not in Terraform state. |
| Nodes | Managed node group, 2 x c7i-flex.large (2 vCPU, 4 GiB, on the Free plan's eligible list, 29 pods per node), min 2, max 3, public subnets, NAT gateway disabled. The instance type is a Terraform variable. t3.medium is cheaper (0.0416 vs 0.0848 USD per hour) and passes an EC2 dry-run, but it is not on the eligible list and only a real launch proves the Free plan allows it, so it is not the default. |
| Load balancing | AWS Load Balancer Controller with an ALB Ingress (one ALB). |
| Autoscaling | HPA on CPU (core). Cluster Autoscaler on EKS only, as a short stretch segment: it needs a cloud node group, so it cannot be exercised on kind. A third node costs about 0.05 USD per hour, so money is not the constraint, video time is. |
| GitOps / visuals | Self-hosted Argo CD (free). Four-pane screen: Argo CD UI, HPA watch, pods watch, k6 output. |
| Load test | k6 run from WSL against the ALB DNS name. |
| Local copy | kind in WSL Ubuntu for rehearsal at zero cost, using a NodePort (no ingress controller: the Kubernetes project retired ingress-nginx in March 2026). Chapter 1 (Docker) is recorded fully locally. |

---

## 2. Account and plan options

### What AWS says about new-account free tier (read 2026-11-06)
- Free plan: 100 USD credit at signup plus up to 100 USD more from activities (max 200). Ends at 6 months or when credits run out, whichever is first. Account then closes, data kept 90 days, can upgrade to Paid within that window and remaining credits carry over.
- Credit expiry is stated inconsistently across AWS FAQ answers (6 months in some, 12 in others). Check the Billing console instead of trusting either number.
- EKS, EC2 and Elastic Load Balancing appear in AWS's list of services available in the new sign-up experience's Free Tier. NAT gateway is not named. Whether credits can be spent on the EKS control plane charge is **not stated** on any page I could read.
- Free plan excludes things that could burn credits fast (Reserved Instances, Savings Plans, some Marketplace items) and hardware purchases.
- The FAQ says the Free plan and credits are for new customers only: ineligible "if you have an existing AWS account or have previously had one".

### Options

| Option | Verdict |
|---|---|
| A. Existing personal account (turned out to be on the Free plan with 100 USD credits) | **Chosen.** Whole project costs roughly a coffee and a sandwich, drawn from the credits. Budget alarm created, teardown routine to write. See "Free plan adjustments" below. |
| B. New account with a different email to get Free plan credits | Not recommended. It goes against the stated eligibility rule (you have had an account), carries suspension risk, and saves at most about 10 USD. Also, the account would close on credit exhaustion or at 6 months, in the middle of a goal that is open-ended. |
| C. Company sandbox account (Planet DDS has AWS for Cloud9 and Legwork) | Worth one message if this goal is work-sponsored. Costs are trivial either way. Your call, not needed. |
| D. Skip AWS, run everything on kind locally | Zero cost, but loses the AWS competency angle (VPC, IAM, ECR, ALB, EKS). Keep as the rehearsal and fallback path. |

### Free plan adjustments (decided 2026-11-07)
Checked with `aws freetier get-account-plan-state`: plan FREE, ACTIVE, 100.00 USD credits unspent, ends 2027-05-06.
- **Hard deadline:** the plan ends on 2027-05-06 or when the credits run out, whichever is first, and the account then closes (data kept 90 days, upgrade to Paid within that window keeps remaining credits). Record the video well before that date and never leave a cluster running.
- **Eligible node type:** the Free plan's eligible EC2 types in us-east-1 are c7i-flex.large, m7i-flex.large, t3.micro, t3.small, t4g.micro, t4g.small, t8i.micro and t8i.small. t3.medium is not on the list. Default node type is c7i-flex.large: 4 GiB like t3.medium, 29 pods per node instead of 17 (3 ENIs x 10 IPv4), about 0.043 USD per hour more per node (AWS Price List API, 2026-11-07).
- **Credits check:** run `scripts/aws-status.sh` before and after every session. It prints the remaining credits and anything billable still running. The first run after the first EKS session answers whether the EKS control plane consumes credits (billing data lags up to a day).
- **Stay on the Free plan:** do not join AWS Organizations or set up Control Tower (both auto-upgrade to Paid), and do not buy Savings Plans, Reserved Instances or Marketplace items.
- **Budget:** `eks-demo-monthly-15usd` exists (created 2026-11-07), counts gross usage with credits excluded so it alerts even while credits cover the bill.
- **Quota:** the On-Demand Standard vCPU limit is now 32 (requested 8, AWS granted more). No node-count limit for this project.

---

## 3. Cost model (us-east-1)

Rates used:

| Item | Rate | Source quality |
|---|---|---|
| EKS control plane, standard support | 0.10 USD per hour | AWS pricing page |
| EKS control plane, extended support | 0.60 USD per hour | AWS pricing page |
| c7i-flex.large on-demand (the node type) | 0.0848 USD per hour | AWS Price List API, 2026-11-07 |
| t3.medium on-demand (fallback, not Free plan eligible) | 0.0416 USD per hour (spot about 0.015) | AWS Price List API, 2026-11-07 |
| t3.small on-demand | 0.0208 USD per hour | Vantage |
| NAT gateway | 0.045 USD per hour plus 0.045 USD per GB | AWS VPC page worked example (Ohio) |
| Public IPv4 address | 0.005 USD per hour each | AWS VPC page |
| ALB | 0.0225 USD per hour plus 0.008 USD per LCU-hour | AWS ELB page worked examples |
| EBS gp3 | about 0.08 USD per GB-month | From memory, not verified |

Hourly cost of the recommended build:

| Component | USD per hour |
|---|---|
| EKS control plane | 0.100 |
| 2 x c7i-flex.large | 0.170 |
| 2 node public IPv4 | 0.010 |
| ALB + its 2 public IPs + light LCU | 0.040 |
| 2 x 20 GB gp3 | 0.004 |
| **Total** | **about 0.32** |

- 4-hour session: about 1.30 USD. A day left on: about 7.80 USD. A month left on: about 233 USD.
- Adding a NAT gateway: about +0.045 per hour (about +1.08 per day), which is why we disable it.
- Third node during load test: +0.085 per hour.
- ECR: images are tiny, storage is cents.
- Traffic: k6 to ALB is inbound to AWS (free); responses out are small and inside the monthly free outbound allowance.

Budget for the project: 6 to 8 sessions of about 4 hours (build, 2 rehearsals, recording, retakes) = about 8 to 11 USD at 0.32 per hour, so call it 8 to 13 with slack. The AWS Budget is set at 15 USD (created 2026-11-07): if it alerts, run `scripts/aws-status.sh` before assuming a leak.

### Cost levers, ranked
1. **Tear down after every session** (cluster create takes about 15 to 20 minutes, delete about 10; plan the sessions around that).
2. No NAT gateway (nodes in public subnets with public IPs, locked down by security groups).
3. 2 nodes, not 3. Scale to 3 only for the node-autoscaling stretch segment.
4. Pin a Kubernetes version still in standard support. Per AWS docs read today: 1.34 to 1.37 are in standard support, 1.37 is newest (released 2026-10-01), **1.34 leaves standard support 2026-12-02**, 1.33 and older are already extended (6x control plane fee). Pick 1.36 or 1.37.
5. One ALB, no NLB, no extra load balancers (delete any `Service type=LoadBalancer` you create while experimenting).
6. No Container Insights, no CloudWatch log shipping for the demo (ingestion fees). Use `kubectl logs`.
7. Spot is possible (t3.medium spot about 0.015) but nodes can vanish mid-recording. Not worth saving about 0.05 per hour.
8. EKS Auto Mode is not used: it adds roughly a 12 percent fee on top of EC2 and hides the node layer you want to show.
9. Skip managed Argo CD (EKS Capabilities, 0.03 USD per capability-hour plus 0.0015 per application-hour). Self-hosting it is free and teaches more.

### Guardrails (do these before creating anything)
- AWS Budgets: 15 USD monthly, alerts at 50, 80, 100 percent actual plus a forecast alert, to your email. **Done 2026-11-07** (`eks-demo-monthly-15usd`).
- Tag everything `project=eks-demo` (Terraform AWS provider `default_tags`).
- IAM admin user or Identity Center role with MFA. Do not work as root.
- Check Service Quotas: "Running On-Demand Standard instances" vCPUs. It was 5 (fits 2 nodes of 2 vCPU, not 3); after a request for 8 it is now 32. **Done 2026-11-07.**
- A `teardown.sh` script (section 7) and a calendar reminder at session end.

---

## 4. Target architecture (EKS)

```
Laptop / WSL                      AWS us-east-1 (one VPC, 2 AZs, public subnets, no NAT)
  k6  ---------- HTTP ----------> ALB (created by AWS Load Balancer Controller from an Ingress)
  browser -- port-forward ------> Argo CD (ClusterIP, not exposed)            |
  kubectl / k9s                         EKS control plane (managed)           v
                                        Managed node group: 2 x c7i-flex.large (min 2, max 3)
                                          kube-system: aws-node, kube-proxy, coredns, metrics-server,
                                                       aws-load-balancer-controller, cluster-autoscaler (stretch)
                                          argocd: server, repo-server, application-controller, redis, ...
                                          demo ns: Deployment (HPA 2..10), Service, Ingress,
                                                   ConfigMap, Secret
ECR private repo: demo-app:<semver>-<gitsha>
GitHub repo: manifests (kustomize base + overlays kind / eks)  <-- Argo CD watches this
```

Notes that shape the design:
- **Pod density is the real node-size constraint.** On the default VPC CNI, t3.small allows 11 pods per node and t3.medium 17 (AWS eni-max-pods file). System pods plus Argo CD use roughly 15 to 18 pods. Two t3.medium nodes (34 pod slots) would leave room for an HPA up to 10 pods, t3.small does not fit. We use c7i-flex.large (3 ENIs x 10 IPv4 gives 29 pods per node, 58 slots on two nodes), which is on the Free plan's eligible list.
- Public subnets with no NAT is a **deliberate, stated trade-off**. Say so on camera: production would use private subnets plus NAT or VPC endpoints.
- Argo CD is reached by `kubectl port-forward` (free, nothing exposed). Only the demo app goes through the ALB.
- IAM for the Load Balancer Controller: IRSA (OIDC provider) or EKS Pod Identity. Either is a good on-camera talking point.

---

## 5. Demo storyboard (target 12 to 14 minutes, hard cap 15, recorded in chapters)

Record each chapter separately, then join. Chapter 1 costs nothing and can be recorded any day. Waiting periods (cluster boot, HPA stabilization, scale-down) are cut or sped up in editing.

### Chapter 1: Docker image engineering and debugging (local, about 3.5 min)
- Naive Dockerfile vs multi-stage Dockerfile for the same app. Show `docker images` size drop (for a Go app, hundreds of MB down to roughly 10 to 20 MB). `docker history` to show layers.
- Layer ordering and cache: change source only, rebuild is near instant.
- Secure config: non-root user, minimal or distroless base, pinned base version, `.dockerignore`, no secrets in image, read-only filesystem option.
- Tagging: semver plus git SHA, never `latest` in manifests. Push to ECR.
- Debug drills with the Docker CLI: container exits immediately (`docker logs`, `docker inspect` exit code), wrong env var (`docker exec env`), port not published, volume mount path wrong, OOM kill with `--memory 64m` (exit 137, `docker stats`).

### Chapter 2: Cluster tour (about 1.5 min)
- The Terraform config (briefly), `kubectl get nodes -o wide`, system pods, AWS console view of cluster, node group, VPC and subnets (shows the no-NAT decision), ECR repo.

### Chapter 3: Deploy through Argo CD (about 2 min)
- Repo layout, Argo CD Application (automated sync, prune, self-heal).
- Manifests on screen: Deployment (probes, requests/limits), Service, Ingress (ALB), ConfigMap, Secret, HPA.
- Argo CD resource tree live as everything appears. `curl` the ALB DNS name, show `/config` returning ConfigMap values.

### Chapter 4: Lifecycle and break-fix (about 3 min)
- Rolling update (about 45 s): bump image tag in git, Argo syncs, watch surge and old pods terminate (`maxSurge`, `maxUnavailable`). Roll back with a git revert.
- Three failure drills, about 40 s each, each fixed via a git commit:
  - `ImagePullBackOff`: typo in tag. `kubectl describe pod` events.
  - `CrashLoopBackOff`: `APP_MODE` removed from the config. `kubectl logs --previous`.
  - Readiness probe failing (`FORCE_NOT_READY=true`): pod Running but not Ready, removed from Service endpoints, ALB target unhealthy.
- Cut for time, kept as backups if you want a longer cut: `Pending` (requests too large, `FailedScheduling`), Service selector mismatch (empty endpoints). `OOMKilled` is already shown in Chapter 1 with Docker.

### Chapter 5: Autoscaling (about 3 min, plus 1 min for node scaling if it fits)
- Four panes: Argo CD tree, `kubectl get hpa -w`, `kubectl get pods -w` (or k9s), k6 output.
- k6 ramps up (for example 0 to 50 virtual users over 2 min, hold, then drop to 0). CPU crosses the target, HPA raises replicas 2 to N, Argo CD tree grows, ALB spreads traffic.
- Load stops. Replicas decay after the scale-down stabilization window. Set the window to about 60 seconds for the recording (default is 300), and say why.
- Stretch: make pods go Pending, Cluster Autoscaler grows the node group 2 to 3, then shrinks it later.

### Chapter 6: Teardown and cost recap (about 30 s)
- Delete Argo apps, wait for ALB removal, `terraform destroy`, show Cost Explorer or the Budgets page.

### Mapping to the goal text

| Goal bullet | Covered in |
|---|---|
| Design, build, maintain production-ready images | Ch 1 |
| Multi-stage, layers, minimal base, tagging, secure config | Ch 1 |
| Image lifecycle, caching, registries | Ch 1 (cache, ECR push), Ch 3 (pull on nodes) |
| Troubleshoot startup, networking, volumes, env vars, resources | Ch 1 drills, Ch 4 drills |
| Optimize image size, startup time, runtime | Ch 1 |
| Docker CLI and logging tools | Ch 1 |
| Deployments, Services, ConfigMaps, Secrets, Ingress | Ch 3 |
| Pod crashes, CrashLoopBackOff, pull failures, scheduling, networking | Ch 4 |
| Rolling updates, scaling, probes, requests/limits | Ch 3, 4, 5 |

---

## 6. Sample app

- Tiny HTTP service. Suggest Go (best image-size story: roughly 800 MB naive to about 10 MB final), but any language works. Pick what you can explain fluently.
- Endpoints: `/healthz` (liveness), `/readyz` (readiness, can be flipped to fail), `/work?ms=N` (burns CPU for N ms so the HPA has something to react to), `/config` (prints ConfigMap-sourced env values), `/secret-check` (reports whether the Secret is present, never its value), `/version` (from `APP_VERSION`, so rolling updates are visible).
- Resource settings to tune in rehearsal: CPU request 100m, limit 250m, memory request 64Mi, HPA target 50 percent CPU, min 2, max 10.
- **Argo CD plus HPA gotcha:** omit `spec.replicas` from the Deployment in git when an HPA owns the count. Otherwise Argo CD self-heal fights the HPA and snaps replicas back. Call this out on camera, it is a classic real-world mistake.

---

## 7. Build phases and checklist

### Phase 0: local prerequisites (free, about 1 hour)
Current state of your machine (checked 2026-11-06):
- Present: Docker Desktop (not running right now), kubectl (bundled with Docker Desktop), Terraform, git. WSL2 Ubuntu 24.04 with 8 cores and 11 GB RAM visible. Docker is reachable inside WSL through Docker Desktop integration.
- Missing at the time: AWS CLI v2, helm, kind, k9s, k6, gh (GitHub CLI). eksctl is no longer needed (Terraform chosen).
- **Done 2026-11-06:** kind v0.33.0, kubectl v1.36.6, helm v4.3.1, k9s v0.51.0, k6 v2.3.0 installed in WSL `~/.local/bin` by `scripts/setup-wsl-tools.sh` (checksums verified). **Done 2026-11-07:** gh 2.103.3, Terraform 1.17.1 and AWS CLI 2.39.6 added to the same script and installed in WSL (gh and Terraform by checksum, AWS CLI by GPG signature against the pinned AWS CLI Team key). Still to do: user signs in (`gh auth login`, `aws configure --profile eks-demo`), then repo, Budget, quota check, ECR.
- [ ] Start Docker Desktop, confirm `docker ps` works in WSL.
- [x] Install in WSL Ubuntu: helm, kind, kubectl, k9s, k6 (no sudo, no `unzip` needed).
- [ ] Create a GitHub repo (public is simplest for Argo CD, no credentials needed).

### Phase 1: AWS hygiene (no cluster cost)
- [ ] MFA, non-root identity, `aws configure sso` or access keys stored in a profile (never in the repo).
- [ ] Budget with alerts, tags convention, quota check.
- [ ] `aws eks describe-cluster-versions` to confirm versions in standard support.
- [ ] Create ECR repo.

### Phase 2: build and rehearse locally on kind (free)
- [x] Write app, naive Dockerfile, multi-stage Dockerfile.
- [x] kustomize base plus overlays: `kind` (NodePort, no ingress controller) and `eks` (ALB Ingress annotations, untested until the AWS phase).
- [x] kind cluster in WSL with metrics-server (needs `--kubelet-insecure-tls` on kind only).
- [ ] Argo CD on kind (needs the GitHub repo first).
- [x] HPA and k6 load test rehearsed locally (results in section 11).
- [ ] Rehearse Chapter 4 on kind: rolling update to 0.2.0, ImagePullBackOff, CrashLoopBackOff, readiness failing.
- [ ] Record Chapter 1 (fully local, ready to record: `scripts/docker-drills.sh`).

### Phase 3: EKS dry run (about 2 to 3 hours of cluster time, about 0.5 to 1 USD)
- [ ] `terraform plan` and read it. Confirm no NAT gateway (`enable_nat_gateway = false`) and nodes land in public subnets with public IPs (`map_public_ip_on_launch = true`).
- [ ] `terraform apply`: VPC, EKS, node group, IAM for the Load Balancer Controller and Cluster Autoscaler. Then Helm: metrics-server, AWS Load Balancer Controller, Cluster Autoscaler, Argo CD.
- [ ] Push image to ECR, point the Argo CD Application at the repo, confirm ALB comes up.
- [ ] Run Chapters 3 to 5 once. Note anything that differs from kind.
- [ ] Tear down using the script.

### Phase 4: record (about 3 to 4 hours of cluster time, about 1 USD)
- [ ] Fresh cluster, rehearse once, record chapters 2 to 5 (retakes are cheap, the cluster is 0.24 USD per hour).
- [ ] Tear down immediately after.

### Teardown script requirements (`teardown.sh`)
1. Delete the Argo CD Applications first (or `kubectl delete ingress,svc` in the app namespace) and **wait until the ALB is gone**. If you delete the cluster first, the ALB, its security groups and ENIs are orphaned and block VPC deletion, and the ALB keeps billing.
2. `terraform destroy` (the Helm releases, node group, cluster and VPC go with it).
3. Verify nothing is left: `aws elbv2 describe-load-balancers`, `aws ec2 describe-volumes`, `aws ec2 describe-nat-gateways`, `aws ec2 describe-addresses`, `aws cloudformation list-stacks` filtered to the `project=eks-demo` tag.
4. Check Cost Explorer next day for stragglers.

---

## 8. Visual setup for recording

- Terminal tool with 3 panes (Windows Terminal split, or tmux in WSL): `kubectl get hpa -w`, `kubectl get pods -w` (or k9s), k6 output.
- Browser: Argo CD UI on the application resource tree view, plus the AWS console tabs (EKS, EC2 load balancers).
- Optional: Lens or Headlamp. Skip Prometheus and Grafana for the AWS run (memory-heavy on t3.medium and not needed for the goal). Could be added on kind only.
- Recorder: OBS Studio (free, chapters, 1080p), or Win+Alt+R for quick takes. Zoom the terminal font so the recording is readable.

---

## 9. Local-only fallback

If AWS stalls (quota, permissions), the same storyboard runs on kind in WSL: swap the ALB Ingress for ingress-nginx, ECR for a local registry or Docker Hub, and drop the AWS console segments. Scoring on the goal bullets would be unchanged, since none of them require EKS specifically. Docker Desktop's built-in Kubernetes also works, but kind is easier to script, reset and keep in git.

Local tool comparison (from 2026 community comparisons): kind is fastest to create and destroy and is config-as-code, k3d is the lightest, minikube has the most built-in addons (ingress, metrics-server). All three are fine. kind is recommended here because it matches how clusters are tested in CI.

---

## 10. Unverified items and open decisions

### Unverified (confirm before relying)
- Whether EKS control plane charges can be paid by Free plan credits (not stated by AWS). The account turned out to be on the Free plan, so this now matters a little: check the remaining credits (`aws freetier get-account-plan-state`) after the first run. On the Free plan, using up the credits closes the account instead of billing it; upgrading to Paid within 90 days keeps remaining credits. Joining AWS Organizations or Control Tower upgrades to Paid automatically.
- Whether the Free plan blocks the EKS control plane at creation time. EKS is on AWS's list of services available to new sign-ups, so it should be fine, and the first `terraform apply` fails fast and free if not. (t3.medium question resolved by choosing the eligible c7i-flex.large, see "Free plan adjustments".)
- Terraform VPC module with `enable_nat_gateway = false`, public-only subnets and a managed node group on them. Believed to work (nodes reach the internet through the internet gateway using their public IPs), but not yet tried. The `terraform plan` step in Phase 3 and the first apply settle it.
- NAT gateway rate quoted from an Ohio worked example, not us-east-1 table. EBS rate from memory. ALB and EC2 rates from page examples and Vantage (region inferred).
- AWS Load Balancer Controller default replica count and Argo CD pod count, which drive the pod-density estimate. Count with `kubectl get pods -A` during the dry run.
- Quota level on your account.

### Decisions (resolved 2026-11-06)
1. Region: us-east-1 (no price difference worth chasing).
2. Cluster build tool: Terraform. Teardown is the Argo-first sequence above, then `terraform destroy`.
3. Sample app language: Go.
4. Node autoscaling: Cluster Autoscaler on EKS only, as a stretch segment. Not feasible on kind.
5. Video: 10 to 15 minutes, no format rules from the reviewer.
6. Account: personal account.

---

## 11. Build log

### 2026-11-06: local build and first rehearsal (all verified on this machine)
- Tools: kind v0.33.0, kubectl v1.36.6, helm v4.3.1, k9s v0.51.0, k6 v2.3.0, installed to WSL `~/.local/bin` with checksums verified. Docker Desktop 29.0.1 running, WSL integration working.
- Image sizes: naive `golang:1.26` image **1.42 GB**, multi-stage distroless image **15.7 MB** (about 90x smaller). Runs as UID 65532, `--read-only --cap-drop ALL` works, `HEALTHCHECK` reports healthy.
- Docker drills (`scripts/docker-drills.sh`) all behave as storyboarded: missing `APP_MODE` exits with code 1 and a clear log line; `--memory 64m` plus `/alloc?mb=200` gives `OOMKilled=true`, exit 137.
- kind cluster (1 control plane, 2 workers, Kubernetes v1.36.4) with metrics-server. Deployment came up at 1 replica (no `replicas` in the manifest), then the HPA raised it to the minimum of 2. App reachable on `localhost:8080` through the NodePort mapping.
- Load test (k6, 60 virtual users peak, 190 s): **32,606 requests, 0 failures, avg 192 ms, p95 548 ms**.
- HPA timeline: CPU hit about 236 percent of request; replicas went 2, 4, 8, 10 within about 75 s of the ramp starting. Held at 10 under load. After load stopped, scale-down began about 80 s later (60 s stabilization window plus metrics lag) and was back at 2 about 110 s after load ended. For the video, the scale-down wait is cut or sped up.
- Fixed along the way: my first HPA sampler printed the wrong column (it showed max replicas); `scripts/loadtest.sh` now prints `cpu=` and `replicas=` correctly (fixed after this run, not re-run).
- Not yet exercised: Argo CD, rolling update, the three break-fix drills in Kubernetes, anything on AWS.

### Paused 2026-11-06
Work paused by the user. Nothing is running: the kind cluster `demo` was deleted, Docker Desktop was quit and the WSL VM shut down. Nothing is committed to git and nothing exists on AWS. To resume the local rehearsal: start Docker Desktop, then in WSL run `scripts/kind-up.sh` and `scripts/kind-deploy.sh 0.1.0` (the `demo-app` images may need `scripts/build-local.sh 0.1.0` again if Docker's image store was reset).

### Next
1. Rehearse Chapter 4 on kind (rolling update, ImagePullBackOff, CrashLoopBackOff, readiness).
2. **Done 2026-11-07:** Argo CD (chart 10.14.0, Argo CD v3.6.1) installed on kind with `scripts/rehearsal-up.sh`; the `demo-app` Application watches https://github.com/QuaziF/eks-demo (`main`, path `k8s/overlays/kind`) and is Synced and Healthy. UI: `scripts/argocd-ui.sh`. Next: rehearse step 1 using git pushes (bump the tag in `k8s/overlays/kind`, `scripts/kind-load.sh 0.2.0` first).
3. AWS phase. Done: CLIs installed, `aws login --profile eks-demo` works (IAM user `eks-demo`, us-east-1), Terraform AWS provider reads that profile, account checked clean. Also done 2026-11-07: Budget 15 USD with email alerts, vCPU quota now 32, plan adjusted for the Free plan (c7i-flex.large nodes). Left: ECR repo, then write `terraform/` (VPC, EKS, node group, IAM, Helm add-ons) and `scripts/teardown.sh`.

---

## Sources
- AWS Free Tier: https://aws.amazon.com/free/ and https://aws.amazon.com/free/free-tier-faqs/
- Free plan details: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html
- Services in new sign-up Free Tier: https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html
- EKS pricing: https://aws.amazon.com/eks/pricing/
- VPC (NAT, public IPv4) pricing: https://aws.amazon.com/vpc/pricing/
- ELB pricing: https://aws.amazon.com/elasticloadbalancing/pricing/
- EKS Kubernetes versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- ingress-nginx retirement: https://kubernetes.io/blog/2025/11/11/ingress-Nginx-retirement/
- Max pods per instance: https://github.com/aws/amazon-vpc-cni-k8s/blob/master/misc/eni-max-pods.txt
- Instance prices: https://instances.vantage.sh/aws/ec2/t3.medium (and t3.small, t4g.small, t4g.medium)
