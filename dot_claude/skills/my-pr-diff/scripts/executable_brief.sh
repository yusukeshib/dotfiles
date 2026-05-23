#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

PR=$(resolve_pr "${1:-}")
REPO_ARGS=$(repo_args)

echo "=========================================="
# shellcheck disable=SC2086
gh pr view "$PR" $REPO_ARGS --json number,title,author,state,isDraft,baseRefName,headRefName,additions,deletions,changedFiles,url \
  --jq '"PR #\(.number)  \(.title)\n  by @\(.author.login)  [\(.state)\(if .isDraft then " · draft" else "" end)]  \(.headRefName) → \(.baseRefName)\n  +\(.additions) -\(.deletions) across \(.changedFiles) files\n  \(.url)"'
echo "=========================================="

echo
echo "── Files changed ─────────────────────────"
# shellcheck disable=SC2086
gh pr view "$PR" $REPO_ARGS --json files \
  --jq '.files[] | "  \(.additions | tostring | .[0:6] | tostring)+ \(.deletions | tostring | .[0:6])-  \(.path)"'

echo
"$DIR/comments.sh" "$PR"
