---
name: merge
description: Drive a PR to merge — fix all CI failures, merge conflicts, and review threads (including bots) round after round, without waiting to be told, until merged.
user-invocable: true
---

# Merge

Own the PR until it is merged. Look for new feedback yourself every round.

**Target PR**: the PR given as an argument (number or URL). If none is given,
the PR created in this session. If neither exists, or more than one PR
matches, ask the user which PR to target. Do not infer the target from the
current branch or other open PRs.

1. **Collect**: unresolved review threads (full bodies, via GraphQL), new
   reviews and PR comments, every failing check's actual error from its job
   log (not just the check name), and merge conflicts with the base branch.
2. **Fix all of them**, at the root cause; also fix the same issue elsewhere
   in the diff. Add a test for behavior fixes. Resolve conflicts by merging or
   rebasing onto the latest base, keeping both sides' intent. Ask the user
   only if a fix would change the agreed design.
3. **Push**, then reply to each addressed thread (what changed, test name)
   and resolve it. Leave disagreements open with a reply giving evidence.
4. **Watch** immediately after every push, and also before the first round:
   run `~/.agents/skills/merge/watch_pr.py <pr> [--repo OWNER/REPO]` as a
   supervised background process (in pi: `babysit_run` with a stable name and
   no `idleTimeout`; it is silent while nothing changes). It polls every 20 s
   and exits on the first poll that finds any problem, without waiting for
   the remaining checks. Then act on the exit code:
   - `10` action needed: handle every `EVENT` line (`ci_failure`,
     `conflict`, `review_thread`, `review`, `comment`, `head_changed`), then
     go back to step 1. Pull before fixing if the head changed.
   - `0` ready: all checks green, no conflict, no unanswered feedback, and
     every review bot reviewed the head commit. Go to step 5. If
     `mergeStateStatus=BEHIND`, update the branch and watch again.
   - `20` closed or merged: stop and report.
   - `3` GitHub API failing: retry once, then report the blocker.
   Never end the task or hand back to the user while a watch is running.
   Useful options: `--bot LOGIN` for a review bot that has not reviewed this
   PR yet, `--ignore-author LOGIN` for noisy comment bots (coverage, preview
   deploys), `--bot-timeout SECONDS` (default 900).
5. **Merge** when the watch reports ready and approvals exist (repo's method
   and label policy, no bypass). Confirm merged, clean up.

Report once at the end: rounds, fixes, tests, final state, anything unverified.

## Watch script behavior

- Review threads count as feedback while unresolved and their latest comment
  is not by you, so always reply in a thread you leave open.
- Reviews (with a body or `CHANGES_REQUESTED`) and PR comments count only if
  posted by someone else after the watch started.
- Review bots are those given with `--bot` plus any bot that already reviewed
  this PR; the watch waits for each to review the head commit, up to
  `--bot-timeout` after checks finish.
- Detection latency is the poll interval (`--interval`, default 20 s);
  GitHub offers no push notification without a webhook.
