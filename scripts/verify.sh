#!/usr/bin/env bash
# Static checks that need no cluster: manifests render, Go code is formatted and vets clean.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "$(dirname "$0")/.."

for overlay in kind eks; do
  echo "== kustomize build overlays/${overlay}"
  kubectl kustomize "k8s/overlays/${overlay}" > /dev/null
  echo "ok"
done

echo "== gofmt and go vet (in a throwaway golang container)"
# Stream the source in over stdin: bind mounts from /mnt/c are not visible to the Docker daemon.
tar -C app -cf - . | docker run --rm -i golang:1.26-alpine sh -c '
  mkdir /src && tar -xf - -C /src && cd /src
  unformatted="$(gofmt -l .)"
  if [ -n "$unformatted" ]; then echo "gofmt needed: $unformatted"; exit 1; fi
  go vet ./... && echo "vet ok"
'
