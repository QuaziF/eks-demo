#!/usr/bin/env bash
# Installs pinned CLI tools into ~/.local/bin (no sudo needed). Run inside WSL Ubuntu.
# Every download is checked against the checksum file published by the project; the AWS CLI,
# which publishes a signature instead of a checksum, is verified with GPG against a pinned
# key fingerprint. Safe to re-run (it reinstalls the pinned versions).
set -euo pipefail

KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.36.6
HELM_VERSION=v4.3.1
K9S_VERSION=v0.51.0
K6_VERSION=v2.3.0
GH_VERSION=2.103.3
TERRAFORM_VERSION=1.17.1
AWSCLI_VERSION=2.39.6
# AWS CLI Team signing key (fingerprint from the AWS CLI install docs, expires 2027-07-01).
AWSCLI_KEY_FPR=FB5DB77FD5C118B80511ADA8A6310ACC4672475C

BIN="${HOME}/.local/bin"
CACHE="${HOME}/.cache/eks-demo/downloads"
mkdir -p "${BIN}" "${CACHE}"

# Each tool gets its own fresh download directory.
workdir() {
  local d="${CACHE}/$1"
  rm -rf "${d}"
  mkdir -p "${d}"
  echo "${d}"
}

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

# check_sha <file> <sums-file>: sums-file is either "<hash>" alone or "<hash>  <name>" lines.
check_sha() {
  local file="$1" sums="$2" name expected actual
  name="$(basename "${file}")"
  if [ "$(wc -w < "${sums}")" -eq 1 ]; then
    expected="$(awk '{print $1}' "${sums}")"
  else
    expected="$(awk -v n="${name}" '$2==n || $2=="*"n {print $1; exit}' "${sums}")"
  fi
  [ -n "${expected}" ] || { echo "no checksum found for ${name}" >&2; exit 1; }
  actual="$(sha256sum "${file}" | awk '{print $1}')"
  [ "${expected}" = "${actual}" ] || { echo "CHECKSUM MISMATCH for ${name}" >&2; exit 1; }
  echo "  checksum ok: ${name}"
}

# unzip_py <zip> <dest>: WSL Ubuntu has no unzip and we have no sudo, so extract with python3,
# keeping unix modes and symlinks (zipfile alone drops both).
unzip_py() {
  python3 - "$1" "$2" <<'PY'
import os, stat, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); dest = sys.argv[2]
for i in z.infolist():
    mode = i.external_attr >> 16
    path = os.path.join(dest, i.filename)
    if stat.S_ISLNK(mode):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.lexists(path):
            os.remove(path)
        os.symlink(z.read(i).decode(), path)
        continue
    z.extract(i, dest)
    if mode and not i.is_dir():
        os.chmod(path, mode & 0o7777)
PY
}

echo "kind ${KIND_VERSION}"
d="$(workdir kind)"
fetch "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" "${d}/kind-linux-amd64"
fetch "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64.sha256sum" "${d}/sums"
check_sha "${d}/kind-linux-amd64" "${d}/sums"
install -m 0755 "${d}/kind-linux-amd64" "${BIN}/kind"

echo "kubectl ${KUBECTL_VERSION}"
d="$(workdir kubectl)"
fetch "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" "${d}/kubectl"
fetch "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" "${d}/sums"
check_sha "${d}/kubectl" "${d}/sums"
install -m 0755 "${d}/kubectl" "${BIN}/kubectl"

echo "helm ${HELM_VERSION}"
d="$(workdir helm)"
fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" "${d}/helm-${HELM_VERSION}-linux-amd64.tar.gz"
fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" "${d}/sums"
check_sha "${d}/helm-${HELM_VERSION}-linux-amd64.tar.gz" "${d}/sums"
tar -xzf "${d}/helm-${HELM_VERSION}-linux-amd64.tar.gz" -C "${d}"
install -m 0755 "${d}/linux-amd64/helm" "${BIN}/helm"

echo "k9s ${K9S_VERSION}"
d="$(workdir k9s)"
fetch "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" "${d}/k9s_Linux_amd64.tar.gz"
fetch "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256" "${d}/sums"
check_sha "${d}/k9s_Linux_amd64.tar.gz" "${d}/sums"
mkdir -p "${d}/x" && tar -xzf "${d}/k9s_Linux_amd64.tar.gz" -C "${d}/x"
install -m 0755 "${d}/x/k9s" "${BIN}/k9s"

echo "k6 ${K6_VERSION}"
d="$(workdir k6)"
fetch "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-amd64.tar.gz" "${d}/k6-${K6_VERSION}-linux-amd64.tar.gz"
fetch "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-checksums.txt" "${d}/sums"
check_sha "${d}/k6-${K6_VERSION}-linux-amd64.tar.gz" "${d}/sums"
tar -xzf "${d}/k6-${K6_VERSION}-linux-amd64.tar.gz" -C "${d}"
install -m 0755 "${d}/k6-${K6_VERSION}-linux-amd64/k6" "${BIN}/k6"

echo "gh ${GH_VERSION}"
d="$(workdir gh)"
fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" "${d}/gh_${GH_VERSION}_linux_amd64.tar.gz"
fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" "${d}/sums"
check_sha "${d}/gh_${GH_VERSION}_linux_amd64.tar.gz" "${d}/sums"
tar -xzf "${d}/gh_${GH_VERSION}_linux_amd64.tar.gz" -C "${d}"
install -m 0755 "${d}/gh_${GH_VERSION}_linux_amd64/bin/gh" "${BIN}/gh"

echo "terraform ${TERRAFORM_VERSION}"
d="$(workdir terraform)"
tf_zip="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
fetch "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${tf_zip}" "${d}/${tf_zip}"
fetch "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" "${d}/sums"
check_sha "${d}/${tf_zip}" "${d}/sums"
unzip_py "${d}/${tf_zip}" "${d}/x"
install -m 0755 "${d}/x/terraform" "${BIN}/terraform"

echo "aws cli ${AWSCLI_VERSION}"
d="$(workdir awscli)"
aws_zip="awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"
fetch "https://awscli.amazonaws.com/${aws_zip}" "${d}/${aws_zip}"
fetch "https://awscli.amazonaws.com/${aws_zip}.sig" "${d}/${aws_zip}.sig"
# Trust anchor is the pinned fingerprint: the key is fetched from a keyserver, then both the
# imported key and the signature must resolve to exactly that fingerprint.
export GNUPGHOME="${d}/gnupg"
mkdir -p "${GNUPGHOME}" && chmod 700 "${GNUPGHOME}"
fetch "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${AWSCLI_KEY_FPR}" "${d}/awscli-key.asc"
gpg --batch --quiet --import "${d}/awscli-key.asc" 2>/dev/null
gpg --batch --with-colons --fingerprint "${AWSCLI_KEY_FPR}" 2>/dev/null | grep -q "^fpr:::::::::${AWSCLI_KEY_FPR}:" \
  || { echo "AWS CLI signing key fingerprint mismatch" >&2; exit 1; }
gpg --batch --status-fd 1 --verify "${d}/${aws_zip}.sig" "${d}/${aws_zip}" 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG .* ${AWSCLI_KEY_FPR}\$" \
  || { echo "AWS CLI SIGNATURE CHECK FAILED" >&2; exit 1; }
echo "  signature ok: ${aws_zip}"
unset GNUPGHOME
unzip_py "${d}/${aws_zip}" "${d}/x"
"${d}/x/aws/install" --install-dir "${HOME}/.local/share/aws-cli" --bin-dir "${BIN}" --update >/dev/null

echo
echo "Installed to ${BIN}. Make sure it is on PATH (open a new WSL shell, or: export PATH=\$HOME/.local/bin:\$PATH)"
export PATH="${BIN}:${PATH}"
kind version
kubectl version --client
helm version --short
k9s version --short 2>/dev/null || k9s version | head -3
k6 version
gh --version | head -1
terraform version | head -1
aws --version
