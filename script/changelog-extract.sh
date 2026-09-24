#!/usr/bin/env bash
# Extract the release-notes section for one version from CHANGELOG.md.
#
#   script/changelog-extract.sh <version-or-tag> [changelog-path]
#
# Matches headers of the form "## vX.Y.Z" or "## X.Y.Z" (a leading 'v' is optional on
# both the tag and the header) and prints the body up to the next "## " header. Used by
# .github/workflows/release.yml to fill in the GitHub Release body, so that the release
# notes and CHANGELOG.md can never disagree.
set -euo pipefail

raw="${1:?usage: changelog-extract.sh <version> [changelog]}"
file="${2:-CHANGELOG.md}"
ver="${raw#v}"   # strip a leading 'v' from the tag/version

out="$(
  awk -v ver="$ver" '
    /^##[[:space:]]+v?[0-9]+\.[0-9]+/ {
      line = $0
      sub(/^##[[:space:]]+/, "", line)
      sub(/^v/, "", line)
      split(line, a, /[[:space:]]/)
      if (a[1] == ver) { grab = 1; next }   # our version: start grabbing (skip the header)
      else if (grab)   { exit }             # next version header: stop
    }
    grab { print }
  ' "$file" | awk 'NF { p = 1 } p'          # drop leading blank lines
)"

if [ -z "${out//[$'\t\r\n ']/}" ]; then
  echo "changelog-extract: no section found for '${ver}' in ${file}" >&2
  exit 1
fi

printf '%s\n' "$out"
