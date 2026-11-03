---
name: merge
description: Drive a PR to merge — fix CI failures, merge conflicts, and review threads (including bots) round after round, without waiting to be told, until merged.
user-invocable: true
---

# Merge

Own the PR until it is merged.

**Target**: the PR given as an argument (number or URL); otherwise the PR
created in this session. If neither or several match, ask. Never infer it from
the current branch or other open PRs.

## Loop

1. **Collect** unresolved review threads (full bodies via GraphQL), new reviews
   and comments, each failing check's actual error from its job log, and merge
   conflicts.
2. **Fix** every item at the root cause, including the same issue elsewhere in
   the diff. Add a test for behavior fixes. Resolve conflicts against the
   latest base, keeping both sides' intent. Ask only if a fix would change the
   agreed design.
   Verify locally only with fast, targeted checks (the failing test, lint on
   touched files). Do not run heavy builds, full suites, or GPU jobs that CI
   already runs; push and let CI and the watcher report.
3. **Push**, reply to each addressed thread (what changed, test name), and
   resolve it. Leave disagreements open with a reply giving evidence.
4. **Watch** right after each push, and before the first round: run
   `~/.agents/skills/merge/watch_pr.py <pr> --head <pushed SHA> [--repo
   OWNER/REPO]` as a supervised background process with no idle timeout.
   `--head` is required after a push: GitHub reports the old head for a few
   seconds, and without it a stale green head can be reported ready. Never end
   the task while it runs. On exit:
   - `10` action needed: handle every `EVENT` line, then go to 1. Pull first
     on `head_changed` or `head_mismatch`.
   - `0` ready (green and approved): go to 5. On `mergeStateStatus=BEHIND`,
     update the branch and watch again.
   - `20` closed or merged: stop.
   - `3` API kept failing: report the blocker.
5. **Merge** using the repo's merge method and label policy, without bypass. Confirm the merge and clean up.

Report once at the end: rounds, fixes, tests, final state, anything unverified.

## Watcher

- Polls every 20 s (`--interval`) and exits on the first poll that finds a
  failed check, a conflict, an unresolved thread whose last comment is not
  yours, or a new review or comment by someone else. Reply in every thread you
  leave open, or it fires again.
- Waits for each review bot (bots that already reviewed this PR, plus
  `--bot LOGIN`) to review the head commit, up to `--bot-timeout` (900 s)
  after checks pass.
- Then waits, without a time limit, until the PR is approved: GitHub's
  `reviewDecision` when reviews are required, otherwise another reviewer's
  latest approval with no outstanding change request. Keep it running while
  waiting; new feedback still ends it at once.
- `--ignore-author LOGIN` skips noisy comment bots (coverage, preview deploys).
- Waits out rate limits by itself; `3` means a non-rate-limit failure.
