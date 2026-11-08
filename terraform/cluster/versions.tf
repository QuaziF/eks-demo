terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Every resource that supports tags gets this, so leftovers are easy to find in the console
  # and in Cost Explorer.
  default_tags {
    tags = {
      project = "eks-demo"
    }
  }
}

# Helm talks to the cluster this stack creates. The token comes from the AWS CLI, so the same
# `aws login --profile eks-demo` session that runs Terraform also authenticates Helm.
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region, "--profile", var.aws_profile]
    }
  }
}
