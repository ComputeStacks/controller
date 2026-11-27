#!/usr/bin/env bash
#
# Install the cert-issuer binary for local development.
#
# Production images get cert-issuer from the image pinned in the Dockerfile.
# A workstation runs the controller outside docker, so this copies the binary
# out of that same pinned image into lib/dev/bin/cert-issuer (gitignored),
# where the app looks for it outside production.
#
# Run from anywhere inside the checkout. Safe to re-run: it does nothing when
# the installed binary already matches the Dockerfile's pin, and re-installs
# when the pin changes.
#
# Usage: lib/dev/install-cert-issuer.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dest="${root}/lib/dev/bin/cert-issuer"

image="$(grep -oE 'ghcr\.io/computestacks/cert-issuer:[^ ]+@sha256:[0-9a-f]{64}' "${root}/Dockerfile" | head -1)"
if [ -z "$image" ]; then
  echo "[cert-issuer] ERROR: no pinned cert-issuer image found in ${root}/Dockerfile" >&2
  exit 1
fi
want="${image#*:}"
want="${want%@*}"

# `cert-issuer version` prints JSON: {"commit":...,"version":"0.1.0"}
installed_version() {
  "$1" version 2>/dev/null | grep -oE '"version":"[^"]+"' | cut -d'"' -f4
}

if [ -x "$dest" ] && [ "$(installed_version "$dest")" = "$want" ]; then
  echo "[cert-issuer] ${dest} is already ${want}"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[cert-issuer] ERROR: docker is required to extract the binary" >&2
  exit 1
fi

echo "[cert-issuer] extracting ${want} from ${image}"
mkdir -p "$(dirname "$dest")"
id="$(docker create "$image" version)"
trap 'docker rm "$id" >/dev/null 2>&1 || true' EXIT
docker cp "${id}:/usr/local/bin/cert-issuer" "${dest}.new"
chmod 0755 "${dest}.new"
mv "${dest}.new" "$dest"
echo "[cert-issuer] installed ${dest} (version $(installed_version "$dest"))"
