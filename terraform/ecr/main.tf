# The image registry. Kept in its own stack on purpose: it costs cents per month, so it stays up
# between sessions and the images survive `terraform destroy` of the cluster stack. Tear it down
# only when the whole project is finished (see terraform/README.md).
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type        = string
  default     = "eks-demo"
  description = "Named profile from `aws login --profile eks-demo`. Never a default profile: the work account also uses AWS."
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      project = "eks-demo"
    }
  }
}

resource "aws_ecr_repository" "demo_app" {
  name = "demo-app"

  # A tag is a release. Immutable tags stop `docker push` from silently replacing 0.1.0, and
  # mutable tags are the classic reason a node keeps running a stale image.
  image_tag_mutability = "IMMUTABLE"

  # Lets `terraform destroy` remove the repository even though it still holds images.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "demo_app" {
  repository = aws_ecr_repository.demo_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images, storage is the only cost here"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" {
  value       = aws_ecr_repository.demo_app.repository_url
  description = "Use as the image name in k8s/overlays/eks (newName)."
}
