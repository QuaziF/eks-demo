# Cluster add-ons, installed with Helm from this stack so one `terraform apply` gives a cluster
# that is ready for the demo and one `terraform destroy` removes them again. The order matters:
# the Load Balancer Controller registers a webhook that sees every new Service, so anything that
# creates Services (Argo CD) must wait until the controller is Ready.

# metrics-server (needed by the HPA) is an EKS add-on, see eks.tf.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version
  namespace  = "kube-system"
  timeout    = 600

  set = [
    { name = "clusterName", value = aws_eks_cluster.this.name },
    # With Pod Identity there is no instance metadata shortcut, so tell the controller where it runs.
    { name = "region", value = var.region },
    { name = "vpcId", value = aws_vpc.this.id },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
    # One replica: pod slots and memory are tight, and a demo does not need controller HA.
    { name = "replicaCount", value = "1" },
  ]

  depends_on = [
    aws_eks_node_group.default,
    aws_eks_addon.pod_identity_agent,
    aws_eks_pod_identity_association.lbc,
    aws_iam_role_policy_attachment.lbc,
  ]
}

# Same chart version and values as the kind rehearsal (argocd/values.yaml). The chart comes from
# the OCI registry argo-helm publishes to, not the https repository: that one serves the tarball
# from GitHub releases, which was returning 504 on 2026-11-08.
#
# Optional, off by default (var.install_argocd): the Argo CD on the local kind cluster manages this
# cluster, see scripts/argocd-register-eks.sh. Turn it on for the "Argo CD runs inside the cluster"
# variant of the demo.
resource "helm_release" "argocd" {
  count = var.install_argocd ? 1 : 0

  name             = "argocd"
  repository       = "oci://ghcr.io/argoproj/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600

  values = [file("${path.module}/../../argocd/values.yaml")]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_addon.metrics_server,
  ]
}

resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_chart_version
  namespace  = "kube-system"
  timeout    = 600

  set = concat(
    [
      { name = "autoDiscovery.clusterName", value = aws_eks_cluster.this.name },
      { name = "awsRegion", value = var.region },
      { name = "image.tag", value = var.cluster_autoscaler_image_tag },
      { name = "rbac.serviceAccount.name", value = "cluster-autoscaler" },
    ],
    [for flag, value in var.cluster_autoscaler_extra_args : { name = "extraArgs.${flag}", value = value }],
  )

  depends_on = [
    aws_eks_node_group.default,
    aws_eks_addon.pod_identity_agent,
    aws_eks_pod_identity_association.cluster_autoscaler,
    aws_iam_role_policy_attachment.cluster_autoscaler,
    helm_release.aws_load_balancer_controller,
  ]
}
