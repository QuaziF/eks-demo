resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id

    # Public endpoint, restricted to one IP, so kubectl and Terraform work from home. The private
    # endpoint is on too, so the nodes (which also sit in public subnets) reach the API inside
    # the VPC instead of through the public endpoint that is closed to them.
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = [var.admin_cidr]
  }

  # API access entries instead of the old aws-auth ConfigMap. The identity that creates the
  # cluster (the eks-demo IAM user) becomes cluster admin.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Cost guard: when this version leaves standard support, upgrade instead of silently moving to
  # extended support (0.60 USD per hour instead of 0.10).
  upgrade_policy {
    support_type = "STANDARD"
  }

  # No control plane logs: CloudWatch ingestion is billed. Use `kubectl logs` for the demo.
  enabled_cluster_log_types = []

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id

  instance_types = [var.node_instance_type]
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  disk_size      = var.node_disk_size

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# The agent that hands IAM credentials to pods (EKS Pod Identity). Newer and simpler than IRSA:
# no OIDC provider, just an association between a service account and a role.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.default]
}

# metrics-server, which the HPA needs. Installed as the AWS-managed add-on instead of the Helm
# chart: the chart downloads from GitHub releases, which returned 504 for over an hour on
# 2026-11-08 while the cluster was waiting to be built (billing). The add-on needs nothing outside
# AWS. On kind it is still the Helm chart with --kubelet-insecure-tls (scripts/kind-up.sh).
resource "aws_eks_addon" "metrics_server" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "metrics-server"

  depends_on = [aws_eks_node_group.default]
}
