#!/usr/bin/env bash
# shared helpers
set -euo pipefail

resolve_pr() {
  if [[ -n "${1:-}" ]]; then
    echo "$1"
    return
  fi
  gh pr view --json number -q .number 2>/dev/null || {
    echo "ERROR: no PR number given and no PR found for current branch" >&2
    exit 1
  }
}

repo_args() {
  if [[ -n "${REPO:-}" ]]; then
    echo "--repo $REPO"
  fi
}
