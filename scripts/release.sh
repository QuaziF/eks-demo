#!/usr/bin/env bash
# Releases a new demo-app version with one command, doing what a CI pipeline would do:
#   1. build the image from the committed code
#   2. make it available (kind: load into the nodes, EKS: push to ECR under an immutable tag)
#   3. bump newTag in the Kustomize overlay(s), commit that one change, push it
#   4. wait until Argo CD has synced the new commit and the app is Healthy
# Argo CD deploys only what git says, so the release IS the commit that changes newTag.
# Rollback is the same idea backwards: git revert that commit and push.
#
# Usage: scripts/release.sh <tag> [--kind-only | --eks-only] [--no-push] [--dry-run]
#   <tag>        new version, for example 0.2.0 (never 'latest': ECR tags are immutable)
#   --kind-only  release to the local kind overlay only (no AWS needed)
#   --eks-only   release to the EKS overlay only (no kind needed)
#   --no-push    commit but do not push (Argo CD deploys when you push)
#   --dry-run    run the checks and show the plan, change nothing

set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

usage() { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "release: $*" >&2; exit 1; }

TAG="" ONLY="" PUSH=1 DRY=0
for arg in "$@"; do
  case "${arg}" in
    --kind-only) [ -z "${ONLY}" ] || [ "${ONLY}" = kind ] || die "choose one of --kind-only and --eks-only"; ONLY=kind ;;
    --eks-only)  [ -z "${ONLY}" ] || [ "${ONLY}" = eks ] || die "choose one of --kind-only and --eks-only"; ONLY=eks ;;
    --no-push)   PUSH=0 ;;
    --dry-run)   DRY=1 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          usage >&2; die "unknown option ${arg}" ;;
    *)           [ -z "${TAG}" ] || die "only one tag, got '${TAG}' and '${arg}'"; TAG="${arg}" ;;
  esac
done
[ -n "${TAG}" ] || { usage >&2; exit 1; }
[ "${TAG}" != latest ] || die "'latest' is a mutable tag: Argo CD would see no change and ECR rejects re-pushes. Use a version like 0.2.0"
[[ "${TAG}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "'${TAG}' is not a valid image tag"

case "${ONLY}" in
  kind) TARGETS=(kind) ;;
  eks)  TARGETS=(eks) ;;
  *)    TARGETS=(kind eks) ;;
esac

overlay_file() { echo "k8s/overlays/$1/kustomization.yaml"; }
current_tag() {
  local f; f="$(overlay_file "$1")"
  [ "$(grep -c '^    newTag:' "${f}")" = 1 ] || die "expected exactly one 'newTag:' line (4-space indent) in ${f}"
  awk '/^    newTag:/ {print $2}' "${f}" | tr -d '\r'
}

# Which overlays actually change. One already at this tag is left alone.
TODO=()
for t in "${TARGETS[@]}"; do
  cur="$(current_tag "${t}")"
  if [ "${cur}" = "${TAG}" ]; then
    echo "${t}: already at ${TAG}, skipping"
  else
    echo "${t}: ${cur} -> ${TAG}"
    TODO+=("${t}")
  fi
done

# ---- checks, all before anything is built or changed ----
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
BRANCH="$(awk '/targetRevision:/ {print $2; exit}' argocd/application-kind.yaml | tr -d '\r')"
BRANCH="${BRANCH:-main}"

if [ "${#TODO[@]}" = 0 ]; then
  ahead="$(git rev-list --count "origin/${BRANCH}..HEAD" 2>/dev/null || echo 0)"
  [ "${ahead}" = 0 ] || echo "note: ${ahead} commit(s) are not pushed yet. Run: git push origin ${BRANCH}"
  echo "nothing to release"
  exit 0
fi

[ "$(git branch --show-current)" = "${BRANCH}" ] \
  || die "Argo CD watches '${BRANCH}' but you are on '$(git branch --show-current)'. Switch branches first."
if [ -n "$(git status --porcelain -- app)" ]; then
  git status --short -- app >&2
  die "app/ has uncommitted changes. Commit them first, so the image maps to a commit."
fi
for t in "${TODO[@]}"; do
  [ -z "$(git status --porcelain -- "$(overlay_file "${t}")")" ] \
    || die "$(overlay_file "${t}") has uncommitted changes. Commit or discard them first."
done
if [ "${PUSH}" = 1 ]; then
  git fetch --quiet origin "${BRANCH}" || die "cannot reach origin"
  behind="$(git rev-list --count "HEAD..origin/${BRANCH}")"
  [ "${behind}" = 0 ] || die "${BRANCH} is ${behind} commit(s) behind origin/${BRANCH}. Run git pull first."
fi

for c in docker kubectl; do command -v "${c}" >/dev/null || die "${c} not found (scripts/setup-wsl-tools.sh)"; done
docker info >/dev/null 2>&1 || die "Docker is not running"
for t in "${TODO[@]}"; do
  case "${t}" in
    kind)
      { command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx demo; } \
        || die "the kind cluster 'demo' is not running (scripts/kind-up.sh), or release with --eks-only" ;;
    eks)
      aws sts get-caller-identity >/dev/null 2>&1 \
        || die "not signed in to AWS. Run: aws login --remote --profile ${AWS_PROFILE}, or release with --kind-only" ;;
  esac
done

SHA="$(git rev-parse --short HEAD)"
if [ "${DRY}" = 1 ]; then
  echo
  echo "dry run, nothing changed. A real run would:"
  echo "  build      demo-app:${TAG} from commit ${SHA}"
  for t in "${TODO[@]}"; do
    [ "${t}" = kind ] && echo "  kind       load the image into the kind nodes"
    [ "${t}" = eks ]  && echo "  eks        push the image to ECR (skipped if the tag is already there)"
  done
  echo "  git        set newTag to ${TAG} in: $(for t in "${TODO[@]}"; do printf '%s ' "$(overlay_file "${t}")"; done)"
  if [ "${PUSH}" = 1 ]; then echo "             commit that one change and push to origin/${BRANCH}, then wait for Argo CD"
  else echo "             commit that one change (no push)"; fi
  exit 0
fi

# ---- 1 and 2: the image must exist where the cluster pulls from before git points at it ----
echo
echo "== build demo-app:${TAG} from commit ${SHA}"
bash scripts/build-local.sh "${TAG}"
for t in "${TODO[@]}"; do
  case "${t}" in
    kind) echo; echo "== load into kind";  bash scripts/kind-load.sh "${TAG}" ;;
    eks)  echo; echo "== push to ECR";     bash scripts/ecr-push.sh "${TAG}" ;;
  esac
done

# ---- 3: bump, check the rendered result, commit only those files ----
echo
echo "== bump newTag"
FILES=()
for t in "${TODO[@]}"; do
  f="$(overlay_file "${t}")"
  sed -i "s|^\(    newTag: \).*|\1${TAG}|" "${f}"
  name="$(awk '/^    newName:/ {print $2}' "${f}" | tr -d '\r')"
  rendered="$(kubectl kustomize "k8s/overlays/${t}" | awk '/^ *image:/ {print $2; exit}')"
  if [ "${rendered}" != "${name}:${TAG}" ]; then
    git checkout -- "${f}"
    die "${t} overlay renders '${rendered}', expected '${name}:${TAG}'. File restored, nothing committed."
  fi
  echo "${t}: renders ${rendered}"
  FILES+=("${f}")
done

# Explicit paths: anything else in the working tree (for example the IP that eks-deploy.sh writes
# into argocd/application-eks.yaml) is neither staged nor committed.
git add -- "${FILES[@]}"
git commit -q -m "release: demo-app ${TAG} (${TODO[*]})" \
  -m "Image built from ${SHA}. Argo CD deploys this commit; to roll back, revert it." -- "${FILES[@]}"
echo "committed $(git rev-parse --short HEAD): release: demo-app ${TAG} (${TODO[*]})"

if [ "${PUSH}" = 0 ]; then
  echo "not pushed. Argo CD deploys it when you run: git push origin ${BRANCH}"
  exit 0
fi
git push origin "${BRANCH}" \
  || die "push failed. The release commit is local; fix access, then run: git push origin ${BRANCH}"

# ---- 4: wait for Argo CD ----
# Reads the Applications on the kind hub (it manages both clusters). env -u KUBECONFIG, because a
# shell that exported the EKS kubeconfig no longer has the kind context.
hub() { env -u KUBECONFIG kubectl --context kind-demo "$@"; }
app_of() { case "$1" in kind) echo demo-app ;; eks) echo demo-app-eks ;; esac; }
field() { hub -n argocd get application "$1" -o "jsonpath={$2}" 2>/dev/null || true; }

HEAD_SHA="$(git rev-parse HEAD)"
FAILED=0
for t in "${TODO[@]}"; do
  app="$(app_of "${t}")"
  echo
  if ! hub -n argocd get application "${app}" >/dev/null 2>&1; then
    echo "== ${t}: no Argo CD app '${app}' on the kind hub, nothing to wait for. It deploys ${TAG} whenever it is created."
    continue
  fi
  echo "== ${t}: waiting for Argo CD to roll ${app} out to ${TAG} (up to 4 min)"
  # Ask for a refresh now instead of waiting for the next poll.
  hub -n argocd annotate application "${app}" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  last="" ok=0 streak=0 deadline=$((SECONDS + 240))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    # status.sync.revision is the commit Argo CD last compared against the cluster. (Not
    # operationState.syncResult.revision: that only moves when a sync operation actually ran.)
    seen_rev="$(field "${app}" .status.sync.revision)"
    sync="$(field "${app}" .status.sync.status)"
    health="$(field "${app}" .status.health.status)"
    if [ "${seen_rev}" = "${HEAD_SHA}" ]; then cur="sync=${sync:-?} health=${health:-?}"
    else cur="waiting for Argo CD to see ${HEAD_SHA:0:7} (it has ${seen_rev:0:7})"; fi
    [ "${cur}" = "${last}" ] || { echo "   $(date +%T) ${cur}"; last="${cur}"; }
    # Done = Argo CD has applied this commit (Synced at this revision) and the app is Healthy.
    # Required on two polls in a row, because health can still show the old state for a moment
    # right after a sync.
    if [ "${seen_rev}" = "${HEAD_SHA}" ] && [ "${sync}" = Synced ] && [ "${health}" = Healthy ]; then
      streak=$((streak + 1))
      [ "${streak}" -lt 2 ] || { ok=1; break; }
    else
      streak=0
    fi
    sleep 3
  done
  if [ "${ok}" = 1 ]; then echo "${t}: ${app} is Synced and Healthy on ${TAG}"
  else echo "${t}: ${app} was not Synced and Healthy within 4 min. Check the Argo CD UI (scripts/argocd-ui.sh)."; FAILED=1; fi
done
exit "${FAILED}"
