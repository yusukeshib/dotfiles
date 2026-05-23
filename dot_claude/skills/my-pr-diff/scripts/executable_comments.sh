#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$DIR/_common.sh"

PR=$(resolve_pr "${1:-}")
REPO_ARGS=$(repo_args)

# Determine owner/repo/number for GraphQL
# shellcheck disable=SC2086
meta=$(gh pr view "$PR" $REPO_ARGS --json number,headRepository,headRepositoryOwner,baseRepository -q '{n:.number}')
# Use base repo for threads
# shellcheck disable=SC2086
repo_nwo=$(gh repo view $REPO_ARGS --json nameWithOwner -q .nameWithOwner)
owner=${repo_nwo%/*}
name=${repo_nwo#*/}

echo "=========================================="
echo " PR #$PR  ($repo_nwo)"
echo "=========================================="

echo
echo "── Unresolved review threads ─────────────"
gh api graphql -f query='
  query($owner:String!,$name:String!,$pr:Int!){
    repository(owner:$owner,name:$name){
      pullRequest(number:$pr){
        reviewThreads(first:100){
          nodes{
            id isResolved isOutdated path line
            comments(first:20){
              nodes{ author{login} bodyText createdAt url }
            }
          }
        }
      }
    }
  }' -F owner="$owner" -F name="$name" -F pr="$PR" \
  --jq '
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved | not)
    | "\n[thread \(.id)] \(.path):\(.line // "?")\(if .isOutdated then "  (outdated)" else "" end)\n"
      + ( [.comments.nodes[] | "  • @\(.author.login) \(.createdAt)\n    \(.bodyText | gsub("\n"; "\n    "))\n    \(.url)"] | join("\n") )
  ' || echo "  (none or GraphQL error)"

echo
echo "── Inline review comments (chronological) ─"
# shellcheck disable=SC2086
gh api "repos/$owner/$name/pulls/$PR/comments" --paginate \
  --jq '.[] | "[\(.created_at)] @\(.user.login)  \(.path):\(.line // .original_line)\n  \(.body | gsub("\n"; "\n  "))\n  \(.html_url)\n"' \
  || echo "  (none)"

echo
echo "── Issue (conversation) comments ──────────"
# shellcheck disable=SC2086
gh api "repos/$owner/$name/issues/$PR/comments" --paginate \
  --jq '.[] | "[\(.created_at)] @\(.user.login)\n  \(.body | gsub("\n"; "\n  "))\n  \(.html_url)\n"' \
  || echo "  (none)"
