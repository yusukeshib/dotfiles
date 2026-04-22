---
name: my-pr-feedback
description: Address all unresolved PR review comments, push fixes, and resolve threads
user-invocable: true
disable-model-invocation: true
argument-hint: [pr-number]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
---

# Address PR Review Feedback

Resolve all unresolved review comments on a pull request. If no PR number is given, use the PR for the current branch.

**PR number:** $ARGUMENTS

## Steps

1. **Determine the PR number.** If `$ARGUMENTS` is empty, run `gh pr view --json number --jq .number` to detect it from the current branch.

2. **Fetch the repo owner and name:**
   ```
   gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
   ```

3. **Fetch all unresolved review threads** using the GraphQL API. Use the Write tool to create `/tmp/fetch_threads.graphql` with this query (do NOT use Bash to write it — the GraphQL non-null operators cause shell escaping issues):

   ```
   query($owner: String!, $name: String!, $pr: Int!) {
     repository(owner: $owner, name: $name) {
       pullRequest(number: $pr) {
         reviewThreads(first: 100) {
           nodes {
             id
             isResolved
             comments(first: 10) {
               nodes {
                 body
                 path
                 line
               }
             }
           }
         }
       }
     }
   }
   ```

   Then run:
   ```
   gh api graphql -F query=@/tmp/fetch_threads.graphql -f owner=OWNER -f name=NAME -F pr=NUMBER
   ```

4. **Filter to unresolved threads only** (where `isResolved` is `false`). For each unresolved thread, read the referenced file, understand the feedback, and make the appropriate code fix. Skip threads from bots that are purely informational (e.g. review-level summaries with no actionable code feedback — but DO address inline bot comments that point to specific issues).

5. **Verify the fixes** using the project's own toolchain. Inspect the repo (README, CI config, Makefile, package manifests) to discover which formatters, linters, type checkers, and build/test commands apply, then run them. Common examples:
   - **Rust**: `cargo check --workspace` (or `cargo check -p <crate>` if the workspace check fails due to unrelated issues), `cargo clippy --workspace --all-targets -- -D warnings` (or scoped to affected crates), `cargo fmt --all -- --check`
   - **JavaScript/TypeScript**: `tsc --noEmit`, `eslint .`, `prettier --check .`
   - **Python**: `ruff check .`, `ruff format --check .`, `mypy .`
   - **Go**: `go build ./...`, `go vet ./...`, `gofmt -l .`
   - **Other**: whatever is defined in the project's `Makefile`, `package.json` scripts, `pyproject.toml`, CI config, etc.

   Prefer project-level wrappers (`make check`, `npm run lint`, etc.) when they exist — they often set required environment (e.g. `PKG_CONFIG_PATH`) that bare tool invocations miss.

6. **Commit and push** all fixes in a single commit with a descriptive message.

7. **Resolve each addressed thread** using the GraphQL mutation. Use the Write tool to create `/tmp/resolve_thread.graphql` with this mutation (do NOT use Bash to write it):

   ```
   mutation($id: ID!) {
     resolveReviewThread(input: { threadId: $id }) {
       thread { isResolved }
     }
   }
   ```

   Then for each thread:
   ```
   gh api graphql -F query=@/tmp/resolve_thread.graphql -f id=THREAD_NODE_ID
   ```

   Do this for every thread that was successfully addressed.

## Important

- Read the code before making changes. Understand the existing patterns.
- Only address substantive code feedback. Ignore bot summary comments that don't point to specific code issues.
- If a thread's feedback is already addressed (code was already fixed), still resolve the thread.
- Run checks before pushing to avoid pushing broken code.
- After pushing, always resolve the threads so reviewers see them as handled.
