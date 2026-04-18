---
name: create-pr
description: Format & lint, thoroughly review all code changes, then create a PR
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
---

# Create PR Skill

Prepare the current branch for a pull request by formatting, linting, reviewing all changes, and then opening a PR.

## Prerequisites

- You must be on a feature branch (not the base branch). If on the base branch, ask the user which branch to create.
- There must be committed or staged changes that differ from the base branch.

## Detect project conventions first

Before running any commands, inspect the repo to determine:

- **Base branch** — typically `main` or `master`. Check `git symbolic-ref refs/remotes/origin/HEAD` or fall back to whichever of `main`/`master` exists.
- **Formatter / linter commands** — look for clues:
  - `Makefile` / `justfile` — check for `fmt`, `lint`, `check`, `test` targets. Prefer these when present (they often set required env vars).
  - `package.json` scripts — `lint`, `format`, `typecheck`, `test`.
  - `Cargo.toml` → `cargo fmt --all`, `cargo clippy --all-targets -- -D warnings`, `cargo test`.
  - `pyproject.toml` / `ruff.toml` → `ruff format`, `ruff check`, `pytest`.
  - `go.mod` → `gofmt`, `go vet`, `golangci-lint`, `go test ./...`.
  - `.pre-commit-config.yaml` → `pre-commit run --all-files`.
  - CI config (`.github/workflows/*.yml`, `.gitlab-ci.yml`) — mirrors the checks that will run on the PR.
- **Project conventions** — read `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` if present.

If nothing is detected, ask the user which commands to run rather than guessing.

## Workflow

### Phase 1: Format

Run the project's formatter to auto-fix style. If files were modified, stage and commit them with a conventional message (e.g. `style: apply formatter`).

### Phase 2: Lint / static checks

Run the project's linter(s) and type checker(s). If warnings/errors are reported:

1. Fix each issue in the source.
2. Re-run until clean.
3. Stage and commit the fixes (e.g. `fix: resolve lint warnings`).

If the project has a test suite that runs quickly, run it here too and fix any failures before proceeding.

### Phase 3: Thorough code review

Review **every changed file** compared to the base branch.

1. Get the full diff and file list:
   ```bash
   git diff <base>...HEAD
   git diff --name-only <base>...HEAD
   ```

2. For each changed file, read the **full file** (not just the diff) to understand context. Evaluate every change against these criteria:

   - **Correctness** — Does the logic do what it's supposed to? Edge cases handled? Off-by-one errors?
   - **Error handling** — Are errors propagated properly? Any calls that could panic/throw in production?
   - **Performance** — Unnecessary allocations, redundant work, obvious O(n²) patterns?
   - **Security** — Command injection, path traversal, SQL injection, XSS, unvalidated input at trust boundaries?
   - **Project conventions** — Does the code follow conventions documented in `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` and match patterns already in the codebase?
   - **Tests** — Bug fixes should include regression tests. New features should have test coverage.
   - **Dead code** — Unused imports, unreachable branches, stale code, leftover debug prints?

3. If the diff is large (>20 files), dispatch Agent subagents to review groups of files in parallel.

4. If issues are found:
   - Fix all High and Medium priority issues directly in the code.
   - After fixing, re-run the formatter, linter, and tests to confirm nothing regressed.
   - Stage and commit fixes (e.g. `fix: address code review findings`).

5. Compile a review summary to include in the PR description. Note any Low priority items intentionally left unfixed.

### Phase 4: Create PR

1. Push the branch:
   ```bash
   git push -u origin HEAD
   ```

2. Determine a concise PR title (under 70 characters) from the commit history:
   ```bash
   git log <base>..HEAD --oneline
   ```

3. Create the PR using `gh`:
   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   <1-3 bullet points describing what this PR does and why>

   ## Code Review
   <Summary of the review — issues found and fixed, or confirmation that no issues were found>

   ### Review Checklist
   - [x] Formatter — passed
   - [x] Linter / static checks — passed (warnings: <count found and fixed, or "none">)
   - [x] Tests — <passed / not run / N/A>
   - [x] Full diff reviewed against: correctness, error handling, performance, security, conventions, tests, dead code

   <If any Low priority items were left unfixed:>
   ### Notes for Reviewer
   <List any items intentionally left for future work>

   ## Test plan
   <How to verify this PR — specific commands, manual steps, or CI checks>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

4. Print the PR URL so the user can see it.

## Important

- Always read full files for context, not just diffs — a change may break invariants elsewhere in the file.
- Do NOT skip the review phase. Every changed line must be evaluated.
- If checks fail after your fixes, investigate and fix — do not push broken code.
- Do not bypass hooks (`--no-verify`) or skip signing unless the user explicitly asks.
- If there are no changes compared to the base branch, inform the user and stop.
