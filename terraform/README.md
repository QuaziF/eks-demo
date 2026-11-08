# Terraform

Two stacks with separate state, because they have different lifetimes.

| Stack | Creates | Cost | Lifetime |
|---|---|---|---|
| `ecr/` | One private ECR repository (`demo-app`, immutable tags, keeps the last 10 images) | cents per month | Stays up between sessions, so images survive. Destroy at the very end of the project. |
| `cluster/` | VPC (2 public subnets, no NAT), EKS 1.36, one managed node group (2 x c7i-flex.large), IAM, EKS Pod Identity, the metrics-server add-on, and Helm releases for the AWS Load Balancer Controller and, optionally, Argo CD (`install_argocd`, off by default, from the ghcr.io OCI registry) and Cluster Autoscaler | **about 0.32 USD per hour** (about 7.80 per day) | Create for a session, destroy when it ends. |

State is local (`terraform.tfstate` next to the code, ignored by git). Losing it while a cluster is up orphans the resources, which is what `scripts/aws-status.sh` is for.

## Everyday commands

Sign in first (about 12 hours per login): `aws login --remote --profile eks-demo`.

```bash
terraform -chdir=terraform/ecr init && terraform -chdir=terraform/ecr apply   # once
scripts/ecr-push.sh 0.1.0        # push an image that is in the local Docker store

scripts/eks-up.sh                # COSTS MONEY from here: about 15 to 20 min to create
scripts/eks-deploy.sh            # deploy the app through the Argo CD on kind, prints the ALB URL
scripts/teardown.sh              # always, when the session ends: AWS only, the local kind cluster stays up
scripts/teardown.sh --all        # AWS first, then the local kind cluster too (only if AWS is ALL CLEAR)
scripts/aws-status.sh            # credits left, and ALL CLEAR or what is still running
```

`eks-up.sh` detects your public IP and passes it as `admin_cidr`, so only your address can reach the Kubernetes API. It writes a separate kubeconfig (`~/.kube/eks-demo.config`), so plain `kubectl` keeps pointing at kind until you run `export KUBECONFIG=~/.kube/eks-demo.config`.

## Which Argo CD manages EKS

By default the Argo CD on the local kind cluster does (hub and spoke): `scripts/eks-deploy.sh` registers EKS there as the cluster `eks-demo` and applies `argocd/application-eks.yaml` as the app `demo-app-eks`. No Argo CD is installed in EKS, which saves four pods and about two minutes of billed apply time per session. To run one inside the cluster instead: `TF_VAR_install_argocd=true scripts/eks-up.sh`. Trade-off of the default: the hub reaches the EKS API through your home connection, so it depends on your laptop being on and your public IP staying the same.

## Why teardown is a script and not just `terraform destroy`

The Load Balancer Controller creates the ALB from the Ingress. Terraform does not know about it. Destroying the cluster first would leave the ALB running (about 0.04 USD per hour) and its network interfaces would block the VPC from being deleted. `scripts/teardown.sh` deletes the EKS app from the Argo CD on kind first (its self-heal would recreate an Ingress deleted by hand), then any other Argo CD Applications and Ingress in EKS, waits until the ALB and its security groups are gone, then runs `terraform destroy`, then runs the status check. It touches only AWS (and the EKS entries in the kind Argo CD): the local kind cluster keeps running unless you pass `--all`.

## Design choices worth saying out loud

- **No NAT gateway.** Nodes sit in public subnets with public IPs (about 1 USD per day saved). Security groups still block all inbound traffic. Production would use private subnets with NAT or VPC endpoints.
- **API endpoint restricted to one IP**, with the private endpoint on as well so the nodes still reach the control plane.
- **Pod Identity instead of IRSA** for the controller's AWS permissions: no OIDC provider to manage, just a role and an association.
- **`upgrade_policy.support_type = STANDARD`**: when 1.36 leaves standard support the cluster is upgraded instead of silently moving to extended support (0.60 USD per hour instead of 0.10).
- **The Cluster Autoscaler is on by default**, because the EKS overlay requests 350m CPU per pod (kind keeps 100m) so that more than 8 pods no longer fit on the two nodes. It only adds a node when a pod is Pending. Its flags (`cluster_autoscaler_extra_args`) are demo values that make a node leaving visible in a short video; they would make nodes flap in a real cluster.
- **No control plane logging, no Container Insights**: CloudWatch ingestion is billed.
- **Helm chart versions are pinned** in `cluster/variables.tf`, so a rehearsal and the recording install the same thing. The Argo CD chart version matches `scripts/argocd-install.sh`.
- **The load balancer controller's IAM policy** (`cluster/policies/lbc-iam-policy.json`) is the unmodified file published by the controller project for chart v3.6.2. Update both together.
