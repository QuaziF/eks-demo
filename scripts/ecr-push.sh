#!/usr/bin/env bash
# Pushes demo-app:<version> from the local Docker image store to the ECR repository that
# terraform/ecr creates. The repository uses immutable tags, so a version that is already in ECR
# is skipped, not overwritten.
# Usage: scripts/ecr-push.sh [version]   (default 0.1.0; builds the image first if Docker lacks it)
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Not signed in to AWS. Run: aws login --remote --profile ${AWS_PROFILE}" >&2
  exit 1
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="${REGISTRY}/demo-app"

if aws ecr describe-images --repository-name demo-app --image-ids "imageTag=${VERSION}" >/dev/null 2>&1; then
  echo "demo-app:${VERSION} is already in ECR (tags are immutable), nothing to push"
  exit 0
fi

if ! docker image inspect "demo-app:${VERSION}" >/dev/null 2>&1; then
  echo "demo-app:${VERSION} is not in Docker, building it"
  scripts/build-local.sh "${VERSION}"
fi

# Docker Desktop's credential helper fails when called from WSL ("The stub received bad data"),
# so log in with a throwaway config directory instead. The 12-hour token lives in that directory
# only, and it is deleted when the script ends.
DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
trap 'rm -rf "${DOCKER_CONFIG}"' EXIT
aws ecr get-login-password | docker login --username AWS --password-stdin "${REGISTRY}"

docker tag "demo-app:${VERSION}" "${REPO}:${VERSION}"
docker push "${REPO}:${VERSION}"

echo
aws ecr describe-images --repository-name demo-app \
  --query 'sort_by(imageDetails,&imagePushedAt)[].[imageTags[0],imageSizeInBytes,imagePushedAt]' --output table
echo "image: ${REPO}:${VERSION}"
