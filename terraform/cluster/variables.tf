variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type        = string
  default     = "eks-demo"
  description = "Named profile from `aws login --profile eks-demo`."
}

variable "cluster_name" {
  type    = string
  default = "eks-demo"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "Must be in standard support (extended support costs 6x on the control plane). Same minor as the kind cluster, so what was rehearsed is what runs."
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP as a /32. Only this address can reach the Kubernetes API from the internet. scripts/eks-up.sh fills it in."

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be a single address in CIDR form, for example 203.0.113.10/32."
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "Two zones, EKS needs at least two. us-east-1e is avoided on purpose (EKS cannot place control plane network interfaces there)."
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "node_instance_type" {
  type        = string
  default     = "c7i-flex.large"
  description = "Free plan eligible, 4 GiB, 29 pods per node. t3.medium is cheaper but not on the Free plan's eligible list."
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Initial size only. Terraform ignores later changes, because Cluster Autoscaler owns the number once it runs."
}

variable "node_disk_size" {
  type    = number
  default = 20
}

variable "enable_cluster_autoscaler" {
  type        = bool
  default     = true
  description = "Creates the Cluster Autoscaler's IAM role and installs its Helm chart. On by default because the EKS overlay raises each pod's CPU request (350m) so that more than 8 pods no longer fit on two nodes: without the autoscaler the extra pods would stay Pending forever."
}

variable "cluster_autoscaler_image_tag" {
  type        = string
  default     = "v1.36.2"
  description = "Cluster Autoscaler minor version must match the Kubernetes minor version. Checked on 2026-11-08: v1.36.0, v1.36.1 and v1.36.2 exist in registry.k8s.io/autoscaling/cluster-autoscaler."
}

variable "cluster_autoscaler_extra_args" {
  type = map(string)
  default = {
    # Demo values, so a node being added and then removed fits in a short video. The defaults are
    # scan-interval 10s, scale-down-delay-after-add 10m, scale-down-unneeded-time 10m. Do not use
    # these in a real cluster: they invite nodes to flap. None of them changes WHEN a node is added
    # (that is always "a pod is Pending because nothing fits"), only how fast it reacts.
    "scan-interval"              = "5s"
    "scale-down-delay-after-add" = "1m"
    "scale-down-unneeded-time"   = "1m"
    # Found in the first run: the autoscaler looks at an extra node as soon as the load stops, while
    # the HPA has not removed the old pods yet and the other nodes are still full, so removing it
    # "can reschedule 0 of 1 pods". It then waits this long (default 5m) before looking again, so
    # the node stayed for 5 minutes after the pods were gone. 30s makes the node leave about a
    # minute after the pods do.
    "unremovable-node-recheck-timeout" = "30s"
  }
  description = "Extra Cluster Autoscaler flags, passed to the chart as extraArgs."
}

# Chart versions are pinned so a rehearsal and the recording install the same thing.
variable "lbc_chart_version" {
  type    = string
  default = "3.6.2"
}

variable "install_argocd" {
  type        = bool
  default     = false
  description = "Install a second Argo CD inside EKS. Off by default: the Argo CD on the local kind cluster manages EKS (scripts/eks-deploy.sh), which keeps four pods and about two minutes of billed apply time out of every session. Turn on with TF_VAR_install_argocd=true scripts/eks-up.sh."
}

variable "argocd_chart_version" {
  type        = string
  default     = "10.14.0"
  description = "Same chart version as scripts/argocd-install.sh uses on kind."
}

variable "cluster_autoscaler_chart_version" {
  type    = string
  default = "9.60.0"
}
