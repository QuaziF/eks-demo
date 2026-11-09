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
  browser -- port-forward ------> Argo CD on kind (the hub, manages EKS too)  |
  kubectl / k9s                         EKS control plane (managed)           v
                                        Managed node group: 2 x c7i-flex.large (min 2, max 3)
                                          kube-system: aws-node, kube-proxy, coredns, metrics-server,
                                                       aws-load-balancer-controller, cluster-autoscaler (stretch)
                                          argocd: not installed by default (var.install_argocd)
                                          demo ns: Deployment (HPA 2..10), Service, Ingress,
                                                   ConfigMap, Secret
ECR private repo: demo-app:<semver>-<gitsha>
GitHub repo: manifests (kustomize base + overlays kind / eks)  <-- Argo CD watches this
```

Notes that shape the design:
- **Pod density is the real node-size constraint.** On the default VPC CNI, t3.small allows 11 pods per node and t3.medium 17 (AWS eni-max-pods file). System pods plus Argo CD use roughly 15 to 18 pods. Two t3.medium nodes (34 pod slots) would leave room for an HPA up to 10 pods, t3.small does not fit. We use c7i-flex.large (3 ENIs x 10 IPv4 gives 29 pods per node, 58 slots on two nodes), which is on the Free plan's eligible list.
- Public subnets with no NAT is a **deliberate, stated trade-off**. Say so on camera: production would use private subnets plus NAT or VPC endpoints.
- **Argo CD runs on the local kind cluster and manages both clusters** (hub and spoke, decided 2026-11-08): `scripts/argocd-register-eks.sh` registers EKS as the cluster `eks-demo`, and the app `demo-app-eks` (destination `eks-demo`) sits next to the kind app `demo-app` in one UI. It is reached by `kubectl port-forward` (nothing exposed); only the demo app goes through the ALB. Trade-offs: the hub reaches the EKS API through your home connection, so it needs your laptop on and your public IP unchanged; the registered token is long-lived and has full rights on EKS (it lives in a Secret on local kind and dies with the cluster); teardown must delete the EKS app from the hub first, or its self-heal recreates the ALB. An Argo CD inside EKS is optional: `TF_VAR_install_argocd=true`.
- IAM for the Load Balancer Controller: IRSA (OIDC provider) or EKS Pod Identity. Either is a good on-camera talking point.

---

## 5. Demo storyboard (target 12 to 14 minutes, hard cap 15, recorded in chapters)

Record each chapter separately, then join. Chapter 1 costs nothing and can be recorded any day. Waiting periods (cluster boot, HPA stabilization, scale-down) are cut or sped up in editing.

### Chapter 1: The image, before and after (local, about 3 min; shortened 2026-11-08)
The demo is about Kubernetes, so the intro and this chapter together stay at about 4 minutes and hand over to Chapter 2. Guide: `docs/recording/ch1-docker.md`.
- Naive Dockerfile vs multi-stage Dockerfile side by side in the editor: full Debian and compiler, root, `COPY . .` first, vs two stages, dependencies before source, distroless, non-root, labels, exec-form entrypoint.
- Proof in the terminal: `docker images` (1.42 GB vs 15.7 MB, content size 341 MB vs 3.56 MB), `id` as root vs no shell at all, the Trivy verdict (119 HIGH or CRITICAL vs none).
- Tagging and registry: version and commit labels, never `latest`, ECR immutable tags, the two versions the cluster runs.
- The long version (live cache demo, push to ECR, Docker debugging drills for startup failures, env vars, ports, volumes, OOM and CPU limits, graceful stop) is optional: `docs/recording/ch1x-docker-extended.md`.

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
- Rehearsed on kind 2026-11-07, all four steps work as written, with zero failed requests; see the build log for timings. Argo CD polls every 30 s, so click Refresh in the UI right after each push. With `progressDeadlineSeconds: 60`, Argo CD turns red 60 s after a failing sync, so give each drill about a minute on screen.
- Cut for time, kept as backups if you want a longer cut: `Pending` (requests too large, `FailedScheduling`), Service selector mismatch (empty endpoints). `OOMKilled` is only shown in the optional extended Docker chapter (`docs/recording/ch1x-docker-extended.md`), not in the short Chapter 1.

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
- [ ] Record Chapter 1 (short before and after, fully local, ready to record: `scripts/rec-prep.sh ch1`, guide `docs/recording/ch1-docker.md`).

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
- Not yet exercised (as of this entry): Argo CD, rolling update, the three break-fix drills in Kubernetes, anything on AWS. The Argo CD and Chapter 4 items are done in the next entry.

### 2026-11-07: Chapter 4 rehearsed on kind through Argo CD (all verified)
Every change below was a git commit pushed to `main` and synced by Argo CD (automated sync). A request every 0.2 s ran against `localhost:8080` through each drill to see whether users would notice.
- **Rolling update 0.1.0 to 0.2.0** (after `scripts/kind-load.sh 0.2.0`): Argo saw the push after 33 s, the rollout then took about 15 s (surge pod Ready in about 8 s, old pod out, second surge, second old out). 250 requests, 0 failed. Answers switched from 0.1.0 to 0.2.0 with a short overlap, which is the visible proof of a rolling update.
- **ImagePullBackOff** (tag 0.3.0 does not exist): new pod `ErrImagePull`, then `ImagePullBackOff`; the two old pods kept serving. `kubectl describe pod` events show "Failed to pull image". Fixed with `git revert`; rollout finished about 30 s after the sync. 459 requests, 0 failed.
- **CrashLoopBackOff** (`APP_MODE` removed from `config.env`): the generated ConfigMap name changes with the content hash, so a new ReplicaSet starts by itself. The new pod exits with code 1 and shows `CrashLoopBackOff` with 3 restarts after about 45 s; `kubectl logs` shows the `missing required environment variable` line (`--previous` was not tried). Fixed with `git revert`. 528 requests, 0 failed.
- **Readiness failure** (`FORCE_NOT_READY=true`): new pod `Running` but `0/1`; events show `Readiness probe failed: HTTP probe failed with statuscode: 503`; the Service endpoints list only the two old pod IPs. Fixed with `git revert`. 532 requests, 0 failed.
- **Why nothing failed for users:** `maxUnavailable: 0` with `maxSurge: 1` never removes an old pod until a new one is Ready. Worth saying on camera.
- **Timing for the video:** after a push, Argo CD took 7 to 39 s to notice (30 s poll plus up to 10 s jitter). Click Refresh in the UI to skip the wait, or cut it in editing.
- **Finding:** in all three failures Argo CD showed health `Progressing` (amber), not `Degraded` (red), because a Deployment's `progressDeadlineSeconds` defaults to 600 s.
- **Fix applied (user approved):** `progressDeadlineSeconds: 60` in `k8s/base/deployment.yaml`. It is a spec field, not part of the pod template, so pushing it rolled nothing. Re-ran the readiness drill: Argo CD went `Progressing`, then `Degraded` exactly 60 s after the sync (Deployment condition `Progressing=False ProgressDeadlineExceeded`, old pods still serving, 713 of 713 requests OK). A `git revert` brought it back to `Healthy` right after the rollout finished.
- **Checked that the 60 s deadline does not break Chapter 5:** full k6 run (60 virtual users, 190 s, 35,093 requests, 0 failed, p95 541 ms) with Argo CD health sampled every 5 s. All 58 samples were `Healthy`; HPA went 2, 4, 8, 10 within about 70 s of the ramp and scaled back down during the cooldown. On kind, new pods are Ready in about 8 s, so a scale-up never nears the deadline.
- **Risk on EKS, not yet tested:** in the Cluster Autoscaler stretch, pods stay Pending while a node is added (a few minutes). If that counts as a stalled Deployment, Argo CD could flash `Degraded` for a while. Watch for it in the EKS dry run; if it happens, either accept it (the app really is short of capacity) or raise the value in the EKS overlay only.
- **End state:** kind overlay back at tag 0.1.0 (the storyboard start), app Synced and Healthy. `main` has 14 commits, about 11 of them rehearsal bumps and reverts.

### 2026-11-08: AWS phase started, code written and validated, nothing created yet
- The AWS login had expired (12 h sessions), so no AWS call was possible. Everything below was checked offline with `terraform init` and `terraform validate` (both stacks valid, `terraform fmt` clean). Provider and chart versions looked up that day: AWS provider 6.72.0, Helm provider 3.3.0, AWS Load Balancer Controller chart 3.6.2, metrics-server chart 3.14.0, Cluster Autoscaler chart 9.60.0, Argo CD chart 10.14.0 (10.15.0 exists, same Argo CD v3.6.1, kept to match kind).
- `terraform/ecr/`: persistent private repository `demo-app`, immutable tags, last 10 images kept, scan on push.
- `terraform/cluster/`: VPC with two public subnets and no NAT; EKS 1.36 with the API restricted to one IP (private endpoint also on); managed node group of 2 x c7i-flex.large (min 2, max 3, `desired_size` ignored after creation); Pod Identity agent add-on; IAM for the controller (official policy file for v3.6.2, unmodified) and, behind `enable_cluster_autoscaler`, for Cluster Autoscaler; Helm releases for metrics-server, the controller (1 replica) and Argo CD (same values file as kind), ordered so Argo CD waits for the controller's webhook.
- Scripts: `ecr-push.sh` (skips versions already in ECR), `eks-up.sh` (prints the cost, detects your IP, `terraform apply`, writes a separate kubeconfig `~/.kube/eks-demo.config` so kubectl stays on kind), `teardown.sh` (delete Argo apps and Ingress, wait for the ALB and its security groups, `terraform destroy`, then the status check; `--skip-k8s` escape hatch). `aws-status.sh` now exits 1 when something billable is still running.
- **After sign-in (same day):** account clean, credits 120 USD, quota 32. EKS 1.36 is in standard support until 2027-08-02 (1.37 until 2027-12-01, 1.34 until 2026-12-02). `c7i-flex.large` is offered in us-east-1a, b, c, d and f (not e), 2 vCPU, 4096 MiB, 3 network interfaces x 10 addresses, `FreeTierEligible` true. So the default zones `us-east-1a` and `us-east-1b` are fine.
- **ECR created and loaded (cost: cents):** `terraform/ecr` applied (2 resources), repository `013310058777.dkr.ecr.us-east-1.amazonaws.com/demo-app`, images 0.1.0 and 0.2.0 pushed. Tag 0.3.0 deliberately does not exist (the ImagePullBackOff drill). `ecr-push.sh` now logs in through a throwaway Docker config directory, because Docker Desktop's credential helper fails from WSL ("The stub received bad data"); the token is deleted when the script ends.
- **Cluster plan reviewed, not applied:** 23 resources to add, 0 to change or destroy: VPC, 2 public subnets (`map_public_ip_on_launch` true, ELB role tag), internet gateway, route table, cluster and node IAM roles, controller policy and role, EKS 1.36 (API restricted to the user's IP, private endpoint on, `STANDARD` support policy, API authentication mode), node group (2 x c7i-flex.large, min 2, max 3, AL2023, 20 GiB), Pod Identity agent and association, 3 Helm releases (timeout raised to 600 s). No NAT gateway, no Elastic IP, no load balancer in the plan. No state file exists yet.
- **Unverified until the first apply:** that the Free plan accepts an EKS control plane and c7i-flex.large nodes; that EKS managed node groups tag their Auto Scaling groups with `k8s.io/cluster-autoscaler/<cluster>=owned` automatically (the Cluster Autoscaler IAM policy depends on it, stretch only); the Cluster Autoscaler image tag `v1.36.0`; the teardown script's ALB wait (needs a real ALB to test).
- Not done yet: the `eks` overlay still has the placeholder account ID and `inbound-cidrs`; no `argocd/application-eks.yaml`. Putting your home IP in a public repo is avoidable: the plan is to inject it as an inline Kustomize patch in the Application that the script generates at deploy time.

### 2026-11-08 (later): first EKS run, app deployed and Chapters 4 and 5 rehearsed on EKS
Cluster `eks-demo` created 09:41Z (23 resources, apply took 17 min: control plane 11 min, node group 2 min, controller 1 min, Argo CD 2 min). The Free plan accepted the EKS control plane and the c7i-flex.large nodes. Credits still read 120.0 USD at the time (billing lags; check again later to see whether EKS charges use them).
- **GitHub release downloads returned 504 for over an hour** (from WSL and Windows, while githubstatus said operational). The metrics-server and Argo CD https Helm repos serve their chart tarballs from there, so the first `terraform plan` failed before anything was created (nothing billed). Fix: metrics-server is now the AWS-managed EKS add-on, and Argo CD installs from the OCI registry `oci://ghcr.io/argoproj/argo-helm` (same chart 10.14.0). A `terraform plan` downloads the charts, so it is a free test of chart sources.
- **Verified on the live cluster:** 2 nodes Ready (v1.36.5, us-east-1a and 1b), metrics API works, the controller's webhook and the `alb` IngressClass exist and its Pod Identity credentials work (no permission errors), 15 pods used of 58 slots.
- **Deploy:** only the EKS overlay was pushed to git (real ECR image path; the account id is an identifier, not a secret). The ALB's allowed IP stays the placeholder 203.0.113.10/32 in git and is patched in by the Argo CD Application (`argocd/application-eks.yaml`, applied by `scripts/eks-deploy.sh` with the caller's IP). Result: ALB internet-facing, targets healthy, requests alternate between both pods and both nodes, the ALB's security group allows only the user's /32. The two Elastic IPs that `aws-status.sh` lists once the ALB exists are the ALB's own network interfaces, not leaks.
- **Hub and spoke:** the app moved from an Argo CD inside EKS to the Argo CD on kind. Deleting the old app proved the ALB delete path (the ALB was gone as soon as `kubectl delete application --wait` returned). The Argo CD install inside EKS is now optional (`install_argocd`, default false); applying that removed the release from the live cluster in about 1 minute and the app was untouched. `teardown.sh` is AWS only by default (local kind and its Argo CD keep running), `--all` also removes kind afterwards, and `kind-down.sh` refuses while the EKS cluster exists.
- **Chapter 5 on EKS (k6 through the ALB, 60 virtual users, 190 s):** 18,667 requests, 0 failed, p95 452 ms (about 305 ms of that is the round trip from the laptop). The HPA went 2, 3, 6, 10 within about 70 s of the load starting and back to 2 about 100 s after it stopped. Nodes peaked at about 60 percent CPU each (pods run at about 224 percent of their 100m request, near their 250m limit). Argo CD health on the hub: 57 samples Healthy and 2 brief Progressing (about 5 s each, during scale-out), never Degraded. **For the Cluster Autoscaler stretch:** with max 10 pods of 100m the two nodes never run out of room, so no node is ever added. To trigger it, raise the pod CPU request or the HPA maximum, or cap the node group lower.
- **Chapter 4 on EKS (git push, hub Argo CD, traffic through the ALB):** rolling update 0.1.0 to 0.2.0, ImagePullBackOff (tag 0.3.0 is not in ECR), CrashLoopBackOff (APP_MODE emptied) and readiness failure (FORCE_NOT_READY) all ran with 0 failed requests (92, 206, 209 and 272 requests; only about 1 to 2 requests per second through the ALB, so fewer samples than on kind). The three break-fix drills were scoped to the EKS overlay (a `configMapGenerator` merge), so the local kind app stayed Healthy throughout (checked during the crash drill). Argo CD went Progressing, then Degraded about 60 s after each failing sync, as on kind. Argo noticed pushes after 17 to 86 s (30 s poll plus jitter, slower than kind: click Refresh). The ImagePullBackOff event reads "NotFound ... failed to pull and unpack image".
- **Finding: Argo CD shows the app Degraded for about 35 s after a successful rolling update on EKS.** Cause (sampled per resource): when the update replaces every pod, the HPA cannot read metrics for the new pods yet, its condition becomes `ScalingActive=False / FailedGetResourceMetric`, and Argo CD's built-in HPA health check reports Degraded until metrics-server has scraped them. The app itself is fine (Deployment Available, 0 failed requests). It did not show up in the kind rehearsal, probably because I only sampled Argo a few seconds after each rollout there (not verified); a scale-out does not trigger it because the old pods still have metrics. Both metrics-servers already scrape every 15 s and the EKS add-on has no argument option, so the only lever is Argo CD. **Fixed (user approved, 2026-11-08):** a custom HPA health check in `argocd/values.yaml` (`resource.customizations.health.autoscaling_HorizontalPodAutoscaler`). It is Argo CD v3.6.1's own logic, read from gitops-engine `health_hpa.go` (the built-in check is Go code, not Lua), with one change: `FailedGetResourceMetric` is Progressing instead of Degraded. Applied to the kind hub with a Helm upgrade plus a controller restart. Verified on EKS over two rolling updates with traffic: the app is amber for about 30 s (`FailedGetResourceMetric`), never red, then Healthy; 296 requests, 0 failed. Other HPA failures (failed scale, invalid selector, other metric types) still show Degraded. A custom check replaces the built-in one entirely, so re-compare it when Argo CD is upgraded.
- **ALB deregistration delay (done):** old ALB targets used to stay in `draining` for 5 min after each update (default 300 s). The EKS Ingress now has `alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30`; the controller applied it about 5 s after Argo CD synced it, and old targets now clear about 30 s after an update (measured on two updates), still with 0 failed requests.
- **Cluster Autoscaler stretch, what actually triggers it:** the autoscaler has no CPU or utilization threshold for scaling up. It adds a node only when a pod is Pending because nothing fits. Each node has 1930m CPU allocatable, non-demo pods request about 700m in total, so the demo pods have room for about 3160m, roughly 31 pods at 100m. The 60-user k6 test makes the HPA ask for about 45 pods (pods run at about 224 percent of their request against a 50 percent target), so today the cap of 10 is what stops it. Raising `maxReplicas` in the EKS overlay to about 40 makes pod 32 Pending and the autoscaler add a node (the node group maximum is 3). Other levers: start with one node (`node_min_size` and `node_desired_size` 1, room for about 13 pods), or fill the nodes with idle "balloon" pods that only hold CPU requests. Autoscaler flags only change speed, not the trigger: `scan-interval` (10 s), `new-pod-scale-up-delay` (0 s), and for scale-down `scale-down-unneeded-time` (10 min), `scale-down-delay-after-add` (10 min) and `scale-down-utilization-threshold` (0.5, the only utilization threshold, and for scale-down only). A new node still takes about 2 to 3 min to boot, and during that wait Argo CD will probably show the app red because of `progressDeadlineSeconds: 60` (raise it in the EKS overlay for that take). Untested: the autoscaler image tag, and that the node group's Auto Scaling group carries the discovery tags.
- **Cluster Autoscaler run on EKS (done, CPU-request design, max 12):** the EKS overlay patches the Deployment to a 350m CPU request and 500m limit and the HPA maximum to 12 (kind keeps the base values). Autoscaler v1.36.2 is on by default (`enable_cluster_autoscaler` now true) with demo flags `scan-interval=5s`, `scale-down-delay-after-add=1m`, `scale-down-unneeded-time=1m`. With a 350m request exactly 8 pods fit on the two nodes. Run: k6, 60 virtual users, `HOLD=240s`, through the ALB: 41,955 requests, 0 failed, p95 449 ms. Timeline: the first Pending pod appeared with exactly 8 Running, the autoscaler launched a node 9 s later, the node was Ready 51 s after the first Pending and all 12 pods were Running at that moment (c7i-flex boots in about 45 s, much faster than the 2 to 3 minutes I assumed). The HPA reached 12 and held. Argo CD stayed amber (Progressing) for the 43 s of waiting and never turned red, as predicted: the Deployment's progress deadline is only checked during rollouts, not during a pure scale-out, so `progressDeadlineSeconds: 60` needs no change. Argo CD's Pods view grouped by node shows the node appearing and leaving (confirmed live).
- **Finding: the extra node left 5 minutes after the pods did.** The HPA cut 12 pods to 2 in about 45 s (its 60 s window), but the autoscaler first looked at the new node while the old nodes were still full, so removal "can reschedule only 0 out of 1 pods"; it marked the node unremovable and, by default, waits 5 minutes (`unremovable-node-recheck-timeout`) before looking again. It then needed 1 min unneeded, drained it (one demo pod evicted, Argo amber for 4 s) and the instance was terminated 5 min 27 s after the pods dropped. Fix applied and re-measured: with `unremovable-node-recheck-timeout=30s` the autoscaler found the node removable while the pods were still draining, waited its 1 min, and started removing the node 38 s after the pods reached 2 (it was 5 min 19 s). The node was gone from `kubectl get nodes` 2 min 16 s after the pods reached 2 and 4 min 9 s after the load finished (the last part is EC2 termination, which no flag changes). Same run: 20,299 requests, 0 failed, p95 389 ms; the first Pending again came with exactly 8 Running; all 12 pods were Running 34 s later; Argo CD amber for 42 s, never red. What is left of the 4 min is the HPA's 60 s window (about 70 s after the load) plus the autoscaler's 1 min plus EC2 termination; cut the waiting in editing, or shorten the HPA window and `scale-down-unneeded-time` further if you want it tighter. Also note `scripts/loadtest.sh` keeps sampling for a fixed `COOLDOWN` (480 s in this run) even after the node has gone, so shorten it for a re-run.
- **Teardown, first end-to-end run (done, 12:56Z to 13:11Z, 14 min):** `scripts/teardown.sh` (AWS only) deleted the EKS app from the hub Argo CD (cascade, so the ALB was already gone when it returned), removed the `eks-demo` cluster entry from the hub, found no leftover Ingress or LoadBalancer Services, confirmed no ALB and no controller security groups, then `terraform destroy` removed 27 resources (EKS control plane 3 min, node group 8 min, internet gateway 7 min because of network interfaces still draining) and `aws-status.sh` reported ALL CLEAR (no cluster, instances, NAT gateways, Elastic IPs, load balancers, EBS volumes or extra VPCs; only the ECR repository remains). The local kind cluster and its Argo CD were untouched (3 nodes Ready, `demo-app` Synced and Healthy, no leftover EKS entries). The cluster ran from 09:41Z to about 13:08Z, roughly 1.1 to 1.2 USD by my estimate. Free plan credits read 140.0 USD right after (they were 120.0 before; likely another Free plan activity reward, unverified), before any EKS charges had posted.
- **Smaller notes:** the EKS overlay now carries the autoscaler sizing, so it needs the autoscaler (on by default); the overlay is at tag 0.1.0, both apps Synced and Healthy. About 27 rehearsal commits on `main`.
- **One-command release (added 2026-11-08, `scripts/release.sh <tag>`):** answers "how does new app code get deployed?". Argo CD only renders manifests, so a release is a commit that changes `newTag` in an overlay. The script builds the image, loads it into kind and/or pushes it to ECR (immutable tag), edits `newTag`, checks that `kubectl kustomize` renders the expected image, commits only the overlay file(s), pushes, and waits for the hub Argo CD app to be Synced and Healthy at that commit. It refuses on uncommitted `app/` changes, a wrong or behind branch, a dirty overlay and the tag `latest`. Options: `--kind-only`, `--eks-only`, `--no-push`, `--dry-run`. Tested without publishing anything: dry runs against the real kind cluster and AWS login; the commit, push and guard logic in a throwaway clone with a local bare origin (8 scenarios, including stray staged and dirty files staying out of the release commit and a broken overlay being restored); and the wait loop against the live `demo-app` (success, timeout, missing app). A real release was not run, because it would use up a tag in ECR and push to `main`. Found while testing: `status.operationState.syncResult.revision` only moves when a sync operation actually runs, so the wait uses `status.sync.revision` plus Synced. CI (GitHub Actions with OIDC to ECR) was left out on purpose: this is the manual loop in one command.
- **Recording guides (added 2026-11-08, `docs/recording/`; the lengths and Chapter 1 details below were revised the same day, see the next entry):** a reading script and screen guide for every chapter (0 intro and outro, 1 to 6), written after the user asked for narration, screen setup and navigation, mostly manual commands and edits on screen, scripts only where needed (each with a one-breath overview), no 15 minute cap, and long waits skipped with continuity. Every segment has SCREEN, DO, SAY, WATCH, CUT and IF IT GOES WRONG blocks. The README covers the session plan (A free and local, B the cluster day, C the next day), scenes and window layouts, the time-skip toolkit with a per-wait table, a privacy blur list, the helper scripts and a goal coverage matrix. Length: about 90 minutes if every segment is kept (counted from the narration at 140 words a minute plus typing); a roughly 40 minute main cut, a roughly 56 minute cut that covers every goal bullet, or one video per chapter. New helpers: `scripts/rec-prep.sh` (`ch1` and `eks` pre-flights), `scripts/scan-image.sh` (Trivy 0.76.2 as a container, summary and totals), `scripts/traffic.sh` (live coloured request stream). Chapter 1 commands were rehearsed in full on 2026-11-08 and the numbers in the guide are measured (images 1.42 GB vs 15.7 MB, content size 341 MB vs 3.56 MB, cached rebuild about 1 s vs 43 s naive, OOM exit 137, CPU 397 percent to 24 percent after `docker update --cpus 0.25`, graceful stop 5.3 s with exit 0, Trivy 119 HIGH or CRITICAL on the naive image and 0 on the production one). **Findings:** Docker 29 on this machine applies a 1 second stop timeout to every container (a bare `docker stop` gives exit 137; use `-t 30`), cause not traced; `--mount` with a missing path does not fail on Docker Desktop (it creates the folder), so the guide does not claim it does; ECR repo `demo-app` has scan on push on but no scan exists for 0.1.0 (ScanNotFoundException), so the guide does not show ECR scan results; `docker events` and the `label!=` filter of `docker ps` behave differently from what one expects, the guide uses the tested forms. **Not rehearsed on EKS and flagged in the guides:** Chapter 4.5 (Pending, rehearsed on kind: `FailedScheduling ... Insufficient cpu`, `ProgressDeadlineExceeded` after 60 s), Chapter 4.6 (Service selector mismatch, rehearsed on kind: `Endpoints: <none>`; the prediction that the ALB answers 503 and Argo stays green is unverified), the ECR immutable-tag rejection message and layer-reuse output in 1.5, and the ALB target group during the readiness drill.
- **Chapter 1 shortened (2026-11-08, later):** the user wants the demo to be about Kubernetes, with the intro plus the Docker image part at no more than a few minutes. `docs/recording/ch1-docker.md` is now three segments (1.1 the naive and production Dockerfiles in the editor, 1.2 proof with `docker images`, `id`, `sh` and a Trivy verdict line, 1.3 labels, ECR tag immutability and tag list, then the hand-off to Chapter 2): about 3:10, about 4:15 with the intro (now 1:05). The long version moved to `docs/recording/ch1x-docker-extended.md` (segments renumbered `1x.N`, optional, prepare with `scripts/rec-prep.sh ch1x`). Totals: about 67 min for everything, a main cut of about 31 min, about 40 min covering every Kubernetes bullet. Dropped from the main video: Docker volumes, ports and networking, `logs`/`stats`/`events`, container-level OOM and CPU limits, graceful stop, the live cache demo and the manual ECR push, so volume mounts are no longer covered anywhere in the main video (the recording README coverage table says so). `rec-prep.sh ch1` is now a quick check (about 16 s warm): local `demo-app:0.2.0` and naive images, Trivy warm, AWS sign-in, ECR has 0.1.0 and 0.2.0. Findings while rehearsing: Docker builds carry a fixed 4 to 5 s of overhead on this machine (an unchanged rebuild with every step CACHED takes about 5 s wall clock, a fresh one-line edit about 6 s, the naive rebuild 26 s on the last run and 43 s on an earlier one), so the earlier "1 s versus 43 s" figures were BuildKit step times, not wall clock, and the extended file was corrected; Docker keeps the layers of every earlier edit, so repeating an edit text makes the naive rebuild instant (use a fresh text each take); local `demo-app:0.1.0` has revision label `none` (built before the first commit) while `0.2.0` carries 32b6c5d, hence Chapter 1 uses `0.2.0`; the ECR listing needs `imageDetails[?imageTags]` to hide the untagged BuildKit manifests. Chapters 2 to 5 had their back-references to Chapter 1 reworded (no more "the OOM drill in chapter one").
- **Still open:** the credits check after billing lag (see the teardown note).

### Paused 2026-11-06
Work paused by the user. Nothing is running: the kind cluster `demo` was deleted, Docker Desktop was quit and the WSL VM shut down. Nothing is committed to git and nothing exists on AWS. To resume the local rehearsal: start Docker Desktop, then in WSL run `scripts/kind-up.sh` and `scripts/kind-deploy.sh 0.1.0` (the `demo-app` images may need `scripts/build-local.sh 0.1.0` again if Docker's image store was reset).

### Next
1. **Done 2026-11-07:** Chapter 4 rehearsed on kind through git pushes and Argo CD (rolling update plus the three break-fix drills, 0 failed requests in each). See the 2026-11-07 build log entry. `progressDeadlineSeconds: 60` added so Argo CD turns red (Degraded) during a failed rollout; verified, and the load test stays Healthy.
2. **Done 2026-11-07:** Argo CD (chart 10.14.0, Argo CD v3.6.1) installed on kind with `scripts/rehearsal-up.sh`; the `demo-app` Application watches https://github.com/QuaziF/eks-demo (`main`, path `k8s/overlays/kind`) and is Synced and Healthy. UI: `scripts/argocd-ui.sh`. Also rehearse Chapters 3 and 5 with Argo in the loop (load test while Argo shows the HPA scaling) before the EKS run.
3. **Done 2026-11-08:** AWS phase. ECR repo, `terraform/` (VPC, EKS, node group, IAM, add-ons), the cluster created and verified, app deployed through the hub Argo CD, Chapters 4 and 5 rehearsed on EKS. See the 2026-11-08 build log entries.
4. Open: check Free plan credits again about a day after the run (did EKS charges use them?); commit the new files (`scripts/release.sh`, `rec-prep.sh`, `scan-image.sh`, `traffic.sh`, `docs/recording/`, and the README, PLAN and EKS overlay comment edits; for the new scripts run `git update-index --chmod=+x` after `git add`; the rest of the work is already pushed); then record: Session A (Chapter 1 and the code walkthroughs, free), Session B (the cluster day), Session C (billing numbers and intro and outro). See `docs/recording/README.md`.

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
