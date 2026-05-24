#!/usr/bin/env bash
# Bump version.json to the latest @earendil-works/pi-coding-agent on npm.
#
# Strategy:
#   1. Query the npm registry for the latest version.
#   2. Prefetch the npm tarball to get its sha256 (srcHash).
#   3. Build with a fake npmDepsHash, parse the real one out of the error,
#      write it back, and repeat for srcHash if needed.
#   4. Final `nix build` to confirm the package builds.
#
# Run this whenever you want to upgrade, then `nixy sync`.

set -euo pipefail

cd "$(dirname "$0")"

PKG="@earendil-works/pi-coding-agent"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need jq
need nix
need curl

echo "→ fetching latest version of $PKG …"
VERSION=$(curl -fsSL "https://registry.npmjs.org/${PKG}/latest" | jq -r .version)
echo "  latest: $VERSION"

CURRENT=$(jq -r .version version.json)
if [[ "$VERSION" == "$CURRENT" ]] && [[ "${1:-}" != "--force" ]]; then
  echo "  already on $VERSION (pass --force to recompute hashes)"
  exit 0
fi

TARBALL_URL="https://registry.npmjs.org/${PKG}/-/pi-coding-agent-${VERSION}.tgz"

echo "→ prefetching tarball srcHash …"
SRC_HASH=$(nix store prefetch-file --json --hash-type sha256 "$TARBALL_URL" | jq -r .hash)
echo "  srcHash: $SRC_HASH"

# Write version + srcHash + fake npmDepsHash, then trigger a build to extract
# the real npmDepsHash from nix's error message.
jq -n --arg v "$VERSION" --arg s "$SRC_HASH" --arg n "$FAKE_HASH" \
  '{version:$v, srcHash:$s, npmDepsHash:$n}' > version.json

echo "→ probing for npmDepsHash …"
BUILD_LOG=$(nix build --no-link --print-out-paths .#pi-coding-agent 2>&1 || true)

NPM_DEPS_HASH=$(printf '%s\n' "$BUILD_LOG" \
  | awk '/got: */ {print $NF; exit}')

if [[ -z "$NPM_DEPS_HASH" ]]; then
  echo "could not extract npmDepsHash from build output:" >&2
  printf '%s\n' "$BUILD_LOG" >&2
  exit 1
fi
echo "  npmDepsHash: $NPM_DEPS_HASH"

jq -n --arg v "$VERSION" --arg s "$SRC_HASH" --arg n "$NPM_DEPS_HASH" \
  '{version:$v, srcHash:$s, npmDepsHash:$n}' > version.json

echo "→ final build to verify …"
nix build --no-link .#pi-coding-agent

echo
echo "✓ version.json updated to $VERSION"
echo "  next: run \`nixy sync\` to make it active"
