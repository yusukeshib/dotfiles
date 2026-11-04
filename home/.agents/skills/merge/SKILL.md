---
name: merge
description: Drive a PR, or a whole stack of PRs, to merge — fix CI failures, merge conflicts, stale bases and review threads (including bots) round after round, without waiting to be told, until every target is merged.
user-invocable: true
---

# Merge

Own the targets until they are merged.

**Target**: the PR(s) given as arguments (numbers or URLs); otherwise the PR
created in this session. If neither or several match, ask. Never infer it from
the current branch or other open PRs.

**Stack mode**: when asked to merge a stack, or to merge PRs "as they come",
the target set is dynamic: every open PR of that stack, including PRs opened
later. Watch them all with one `--author` watcher (below). A PR that appears
while you work on another is a target immediately, not after the current one.

## Loop

1. **Collect**, for every target: unresolved review threads (full bodies via
   GraphQL), new reviews and comments, each failing check's actual error from
   its job log, merge conflicts, and the base branch.
2. **Fix** every item at the root cause, including the same issue elsewhere in
   the diff. Add a test for behavior fixes. Resolve conflicts against the
   latest base, keeping both sides' intent. Ask only if a fix would change the
   agreed design.
   Verify locally only with fast, targeted checks (the failing test, lint on
   touched files). Do not run heavy builds, full suites, or GPU jobs that CI
   already runs; push and let CI and the watcher report.
   A failure whose log shows infrastructure trouble (fetch errors, runner
   loss) gets a rerun of the failed job, not a code change.
3. **Push**, then **verify the push took effect** before calling it done. For
   each pushed PR and every descendant in its stack:
   - the remote head equals the SHA you pushed (`git ls-remote`);
   - the PR base is the intended parent, never a `graphite-base/*` restack
     branch (retarget with `gh pr edit --base`, or `gt submit`);
   - `mergeable` is not `CONFLICTING`.
   Restack and push the descendants in the same step. Reply to each addressed
   thread (what changed, test name) and resolve it. Resolve declined findings
   too (won't fix, out of scope, policy): reply with the evidence, then
   resolve. Do not leave threads open.
4. **Watch** right after each push, and before the first round, with one
   supervised background process that covers **every** target and has no idle
   timeout:
   - single PR: `~/.agents/skills/merge/watch_pr.py <pr> --head <pushed SHA>
     [--repo OWNER/REPO]`
   - several PRs or stack mode: `~/.agents/skills/merge/watch_pr.py
     --author @me --until-merged --repo OWNER/REPO [--head PR=SHA ...]`
   `--head` is required after a push: GitHub reports the old head for a few
   seconds, and without it a stale green head can be reported ready. Never end
   the task while it runs. On exit:
   - `10` action needed: handle every `EVENT` line (each names its PR), then
     go to 1. Fetch first on `head_changed` or `head_mismatch`; on `new_pr`,
     add the PR to the targets.
   - `0` ready: go to 5 for the PRs it names. On `mergeStateStatus=BEHIND`,
     update the branch and watch again.
   - `20` a target closed or merged: confirm it merged, clean it up, and watch
     the remaining targets again.
   - `3` API kept failing: report the blocker.
5. **Merge** using the repo's merge method and label policy, without bypass.
   With Graphite, PRs may already be queued automatically; `gt merge
   --dry-run` tells you. Keep watching with `--until-merged` until each PR
   merges, then confirm the merge and clean up.

Report once at the end: rounds, fixes, tests, final state, anything unverified.
In stack mode, also report nothing in between unless the user asks or a
blocker needs a decision.

## Never idle

These rules exist because a session once watched one PR for seven hours while
three newer stack PRs sat with unanswered review comments:

- Never block on one PR while other targets exist. One watcher over all of
  them, not one watcher per PR in sequence.
- At every point at least one watcher covers every open target. If a wait or
  a watcher is interrupted, restart it at once; never end a turn without one.
- No more than 15 minutes may pass without re-listing the open targets and
  re-collecting their state, even if the watcher has not exited.
- "Pushed" is not "done": step 3's verification is part of the push.
- "Ready" is not "merged": the task ends when every target is merged.

## Watcher

- Polls every 20 s (`--interval`), one GraphQL query per PR, and exits on the
  first poll that finds, in any target, a failed check, a conflict, a base
  left on `graphite-base/*` for three polls, an unresolved thread whose last
  comment is not yours, a new review or comment by someone else, a changed
  head, a new PR by `--author`, or a closed/merged target.
- A CANCELLED run superseded by another run of the same check on the same
  commit (workflow concurrency after a restack) is not a failure.
- Waits for each review bot (bots that already reviewed this PR, plus
  `--bot LOGIN`) to review the head commit, up to `--bot-timeout` (900 s)
  after checks pass.
- Then waits, without a time limit, until the PR is approved: GitHub's
  `reviewDecision` when reviews are required, otherwise another reviewer's
  latest approval with no outstanding change request. Keep it running while
  waiting; new feedback still ends it at once.
- `--ignore-author LOGIN` skips noisy comment bots (coverage, preview
  deploys); `graphite-app` is always ignored.
- Waits out rate limits by itself; `3` means a non-rate-limit failure.

## Shell pitfalls

- In zsh, `$VAR:r`, `$VAR:h`, `$VAR:t` and `$VAR:e` are modifiers, so
  `git push origin $SHA:refs/heads/x` pushes a mangled ref. Always write
  `"${SHA}:refs/heads/x"`.
