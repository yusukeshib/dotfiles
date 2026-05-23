#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

PR=$(resolve_pr "${1:-}")
REPO_ARGS=$(repo_args)

LIMIT=5000
if [[ "${FULL:-0}" == "1" ]]; then
  LIMIT=0
fi

render() {
  if command -v delta >/dev/null 2>&1; then
    delta --paging=never --side-by-side --width="${COLUMNS:-200}"
  else
    cat
  fi
}

# shellcheck disable=SC2086
diff_out=$(gh pr diff "$PR" $REPO_ARGS)
total=$(printf '%s\n' "$diff_out" | wc -l | tr -d ' ')

if [[ "$LIMIT" -gt 0 && "$total" -gt "$LIMIT" ]]; then
  echo "# diff truncated: $total lines, showing first $LIMIT (set FULL=1 to see all)" >&2
  printf '%s\n' "$diff_out" | head -n "$LIMIT" | render
else
  printf '%s\n' "$diff_out" | render
fi
