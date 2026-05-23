---
name: my-pr-diff
description: Display a GitHub Pull Request diff with syntax highlighting and list unresolved review comments. Use when the user wants to view, review, or understand changes in a PR.
---

# my-pr-diff

Show a GitHub PR diff with syntax highlighting via `delta`, and list its review/issue comments. GitHub-only. Uses `gh` and `delta`.

## When to use

- "show me the diff of PR 1234"
- "what changed in this PR"
- "show PR comments / unresolved threads"
- Before doing a code review on a PR

## Prerequisites

- `gh` authenticated (`gh auth status`)
- `delta` installed (fallback: plain diff)
- Run inside the target repo's working tree (so `gh` infers the repo), or pass `--repo owner/name`

## Usage

PR number resolution order:
1. Explicit number from user
2. `gh pr view --json number -q .number` (current branch's PR)

### Show diff

```bash
./scripts/diff.sh [PR_NUMBER]
```

- Pipes `gh pr diff <pr>` into `delta --paging=never --side-by-side` when available, otherwise prints plain diff.
- For very large PRs, the script truncates to 5000 lines; use `FULL=1 ./scripts/diff.sh <pr>` to bypass.

### List comments (review + issue + unresolved threads)

```bash
./scripts/comments.sh [PR_NUMBER]
```

Outputs three sections:
1. **Unresolved review threads** — file, line, author, body, thread id
2. **Inline review comments (all)** — chronological
3. **Issue (conversation tab) comments**

### Combined review brief

```bash
./scripts/brief.sh [PR_NUMBER]
```

Prints: PR title/author/state, files changed summary, then comments section. Use this as a quick orientation before writing a review.

## Agent guidance

When loading this skill:
1. Determine the PR number (ask if ambiguous, never guess across repos).
2. Run `./scripts/brief.sh <pr>` first for orientation.
3. Run `./scripts/diff.sh <pr>` only when the user wants to see the actual code, or when you need it to reason about a comment.
4. When summarizing, group changes by file and call out: API/contract changes, new dependencies, test coverage gaps, risky patterns.
5. Do NOT post replies from this skill — it is read-only. For replying, suggest the user run the pi `pr-helper` extension commands (`/pr-comments`) or use `gh api`.

## Notes

- All scripts accept `--repo owner/name` passthrough via `REPO=owner/name`.
- Output is plain text optimized for terminal viewing; do not re-render in markdown code fences when displaying back to the user verbatim.
