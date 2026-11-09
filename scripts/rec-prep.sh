#!/usr/bin/env bash
# Pre-flight checks and warm-ups for the recording sessions. Run it right before you hit record;
# it prints [ok], [warn] or [FAIL] per check and exits 1 if anything failed. Safe to re-run.
#
# Usage: scripts/rec-prep.sh ch1     Chapter 1, the short before and after (local Docker, costs nothing)
#        scripts/rec-prep.sh ch1x    the optional extended Docker chapter (docs/recording/ch1x-docker-extended.md)
#        scripts/rec-prep.sh eks     before scripts/eks-up.sh: Chapters 2 to 6 (checks only, changes nothing)
#
# ch1 does: checks Docker; checks that the local image demo-app:0.2.0 (the one in ECR) exists and refreshes
#   demo-app:naive (cached); warms Trivy's database and the scan results of both images (about 3 minutes
#   the first time, seconds after); checks the AWS sign-in and that ECR holds demo-app 0.1.0 and 0.2.0.
# ch1x does all of ch1, plus: a clean app/ folder; removes leftover demo containers and recreates the
#   ~/ch1 scratch folder for the volume drill; builds the baseline image demo-app:0.1.1 (so the on-camera
#   rebuilds hit the cache); pulls busybox; checks that ports 18080 to 18084 are free.
# eks does: checks the AWS sign-in and that nothing billable is running yet, that the local kind
#   cluster and its Argo CD are healthy, that git is clean and in sync with origin (Chapter 4 pushes
#   commits), that the EKS overlay is at 0.1.0, and that ECR has 0.1.0 and 0.2.0 but NOT 0.3.0
#   (the ImagePullBackOff drill needs 0.3.0 to be missing).
set -uo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

MODE="${1:-}"
FAILS=0
ok()   { echo "[ok]   $*"; }
warn() { echo "[warn] $*"; }
fail() { echo "[FAIL] $*"; FAILS=$((FAILS + 1)); }
HUB=(env -u KUBECONFIG kubectl --context kind-demo)

check_aws() {
  if aws sts get-caller-identity >/dev/null 2>&1; then ok "AWS signed in (profile ${AWS_PROFILE})"
  else fail "not signed in to AWS: aws login --remote --profile ${AWS_PROFILE}"; fi
}

check_git() {
  local branch ahead behind
  branch="$(git branch --show-current)"
  [ "${branch}" = main ] && ok "on branch main" || fail "on branch '${branch}', expected main"
  if [ -z "$(git status --porcelain)" ]; then ok "git working tree is clean"
  else warn "git working tree has uncommitted changes (git status --short)"; fi
  git fetch --quiet origin main 2>/dev/null || warn "could not reach origin"
  ahead="$(git rev-list --count origin/main..HEAD 2>/dev/null || echo ?)"
  behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo ?)"
  if [ "${ahead}" = 0 ] && [ "${behind}" = 0 ]; then ok "in sync with origin/main ($(git rev-parse --short HEAD))"
  else fail "not in sync with origin/main (ahead ${ahead}, behind ${behind})"; fi
}

case "${MODE}" in
ch1|ch1x)
  docker info >/dev/null 2>&1 && ok "Docker is running" || { fail "Docker is not running"; exit 1; }

  # the short chapter: the production image (the same one that is in ECR and runs on the cluster) and the naive one
  if docker image inspect demo-app:0.2.0 >/dev/null 2>&1; then ok "demo-app:0.2.0 exists locally"
  else fail "demo-app:0.2.0 is missing locally (it is the image ECR and the cluster use): scripts/build-local.sh 0.2.0 rebuilds it, but its label then names today's commit"; fi
  if docker build -q -f app/Dockerfile.naive -t demo-app:naive app >/dev/null; then ok "demo-app:naive up to date"
  else fail "build of demo-app:naive failed"; fi

  echo "warming Trivy (first run downloads its database, about 2 minutes; the naive image adds about a minute) ..."
  if scripts/scan-image.sh demo-app:0.2.0 >/dev/null && scripts/scan-image.sh demo-app:naive >/dev/null; then
    ok "Trivy works, its database and both scans are cached (a repeat scan takes about 2 seconds)"
  else fail "Trivy scan failed"; fi

  check_aws
  if aws sts get-caller-identity >/dev/null 2>&1; then
    for t in 0.1.0 0.2.0; do
      aws ecr describe-images --repository-name demo-app --image-ids "imageTag=${t}" >/dev/null 2>&1 \
        && ok "ECR has demo-app:${t}" || fail "ECR is missing demo-app:${t}"
    done
  fi

  if [ "${MODE}" = ch1x ]; then
    # the extended chapter: cache demo, container drills, volume drill
    if [ -z "$(git status --porcelain -- app)" ]; then ok "app/ has no uncommitted changes (image label will name a real commit)"
    else fail "app/ has uncommitted changes: git status --short app"; fi
    [ -z "$(git status --porcelain)" ] && ok "git working tree is clean" || warn "git working tree has uncommitted changes outside app/"

    docker rm -f broken app noport wrongport oom cpu >/dev/null 2>&1 || true
    if [ -d "${HOME}/ch1" ]; then
      docker run --rm -v "${HOME}/ch1:/w" busybox sh -c 'rm -rf /w/* /w/.[!.]*' >/dev/null 2>&1 || true
      rmdir "${HOME}/ch1" 2>/dev/null || true
    fi
    mkdir -p "${HOME}/ch1/out" && ok "scratch folder ~/ch1/out ready (owned by you, mode $(stat -c %a "${HOME}/ch1/out"))"
    ok "demo containers removed"

    SHA="$(git rev-parse --short HEAD)"
    echo "building baseline demo-app:0.1.1 from ${SHA} (cached after the first time) ..."
    if docker build -q -f app/Dockerfile --build-arg VERSION=0.1.1 --build-arg COMMIT="${SHA}" -t demo-app:0.1.1 app >/dev/null; then
      ok "demo-app:0.1.1 built, label revision ${SHA}"
    else fail "build of demo-app:0.1.1 failed"; fi
    docker pull -q busybox >/dev/null 2>&1 && ok "busybox pulled" || fail "could not pull busybox"
    for p in 18080 18081 18082 18083 18084; do
      if ss -ltn 2>/dev/null | grep -q ":${p} "; then fail "port ${p} is in use"; fi
    done
    ok "ports 18080 to 18084 checked"
  fi
  echo; docker images demo-app --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
  ;;

eks)
  check_aws
  if aws sts get-caller-identity >/dev/null 2>&1; then
    if scripts/aws-status.sh >/tmp/aws-status.out 2>&1; then ok "nothing billable is running (aws-status: ALL CLEAR)"
    else fail "aws-status does not say ALL CLEAR: scripts/aws-status.sh"; fi
    for t in 0.1.0 0.2.0; do
      aws ecr describe-images --repository-name demo-app --image-ids "imageTag=${t}" >/dev/null 2>&1 \
        && ok "ECR has demo-app:${t}" || fail "ECR is missing demo-app:${t}"
    done
    if aws ecr describe-images --repository-name demo-app --image-ids imageTag=0.3.0 >/dev/null 2>&1; then
      fail "ECR HAS demo-app:0.3.0, the ImagePullBackOff drill needs it to be missing (immutable tags: it cannot be removed except by deleting the image)"
    else ok "ECR has no demo-app:0.3.0 (good, the pull-failure drill needs that)"; fi
  fi
  if "${HUB[@]}" get nodes >/dev/null 2>&1; then
    ok "kind cluster reachable"
    st="$("${HUB[@]}" -n argocd get application demo-app -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
    [ "${st}" = "Synced/Healthy" ] && ok "Argo CD on kind: demo-app ${st}" || fail "Argo CD on kind: demo-app is '${st}'"
  else fail "kind cluster not reachable: scripts/rehearsal-up.sh"; fi
  check_git
  tag="$(awk '/^    newTag:/ {print $2}' k8s/overlays/eks/kustomization.yaml | tr -d '\r')"
  [ "${tag}" = 0.1.0 ] && ok "EKS overlay is at 0.1.0" || fail "EKS overlay is at '${tag}', expected 0.1.0"
  ip="$(curl -fsS -m 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')"
  [ -n "${ip}" ] && ok "public IP detected (${ip}), the API and the ALB will allow only this address" || fail "could not detect the public IP"
  for c in kubectl helm terraform k6 aws; do command -v "${c}" >/dev/null && ok "${c} found" || fail "${c} not found"; done
  echo
  echo "Next: scripts/eks-up.sh   (the cost clock, about 0.32 USD per hour, starts when you approve the plan)"
  ;;

*)
  sed -n '2,/^set -uo/{/^set -uo/!p}' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
  ;;
esac

echo
if [ "${FAILS}" -eq 0 ]; then echo "READY (no failures)"; else echo "${FAILS} check(s) FAILED"; exit 1; fi
