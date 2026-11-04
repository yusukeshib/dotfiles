#!/usr/bin/env python3
"""Watch GitHub PRs and exit as soon as any of them needs action.

Watches one PR, several PRs (`watch_pr.py 12 13 14`), or a whole stack that
keeps growing (`--author LOGIN`: every open PR by LOGIN, including PRs opened
while watching). One process covers every target, so no PR waits while
another is watched. Each poll runs one GraphQL query per PR and exits on the
first poll that finds, in ANY target:

  - a failing check on the head commit (does not wait for other checks); a
    CANCELLED run superseded by another run of the same check on the same
    commit is not a failure,
  - a merge conflict with the base branch,
  - a base still on a Graphite restack branch (`graphite-base/*`) for three
    polls in a row: the PR diffs against a stale parent and must be
    retargeted or resubmitted,
  - an unresolved review thread whose latest comment is not by you,
  - a new review (with a body or CHANGES_REQUESTED) or PR comment by someone
    else, posted after the watch started,
  - the head commit changing (someone else pushed), or not reaching --head
    within 120 s,
  - a new open PR by --author (exit 10, EVENT new_pr),
  - a target that closed or merged (exit 20).

All events found in that poll are printed, so handle every one of them.

Exit codes:
  0   ready: a PR has all checks green, no conflict, no new feedback, every
      review bot reviewed its head (or --bot-timeout passed), and it is
      approved (--no-approval skips this) but is not yet queued for merge.
      With --until-merged, PRs already queued (auto-merge or Graphite merge
      queue) are not reported ready; the watch continues until they merge.
  10  action needed: see the EVENT lines
  20  a target closed or merged
  3   GitHub API kept failing (not counting rate limits)
  2   usage error

Output lines: "STATUS #n ..." when a PR's state changes, "EVENT <kind> #n ..."
for each problem, "WAIT ..." while rate limited, and a final "RESULT ...".

Rate limits: when GitHub rate-limits the watcher, it sleeps until the GraphQL
budget resets (primary limit) or backs off 60 s doubling to 15 min (secondary
limit), then resumes. When fewer than 100 GraphQL points remain, it stops
polling until the reset so the budget is left for fixing the PR.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime

QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
  rateLimit { remaining resetAt }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      state
      url
      headRefOid
      mergeable
      mergeStateStatus
      reviewDecision
      commits(last: 1) {
        nodes {
          commit {
            oid
            statusCheckRollup {
              contexts(first: 100) {
                nodes {
                  __typename
                  ... on CheckRun { name status conclusion detailsUrl }
                  ... on StatusContext { context state targetUrl }
                }
              }
            }
          }
        }
      }
      reviewThreads(first: 100) {
        nodes {
          isResolved
          path
          line
          comments(last: 50) {
            nodes { id url author { login } }
          }
        }
      }
      reviews(last: 100) {
        nodes {
          id
          state
          body
          url
          author { login __typename }
          commit { oid }
        }
      }
      comments(last: 100) {
        nodes { id url body author { login } }
      }
      baseRefName
      autoMergeRequest { enabledAt }
    }
  }
}
"""

# Informational merge-queue bots: their comments are never feedback.
DEFAULT_IGNORED_AUTHORS = {"graphite-app"}
GRAPHITE_QUEUED = re.compile(r"added this pull request to the \[Graphite merge queue\]")
GRAPHITE_DEQUEUED = re.compile(r"removed this pull request from the \[Graphite merge queue\]")
STALE_BASE = re.compile(r"^graphite-base/")
STALE_BASE_POLLS = 3

FAILED_CONCLUSIONS = {
    "FAILURE",
    "TIMED_OUT",
    "CANCELLED",
    "ACTION_REQUIRED",
    "STARTUP_FAILURE",
}
FAILED_STATUS_STATES = {"FAILURE", "ERROR"}
PENDING_STATUS_STATES = {"PENDING", "EXPECTED"}

EXIT_READY = 0
EXIT_API = 3
EXIT_ACTION = 10
EXIT_CLOSED = 20

MAX_API_FAILURES = 5
HEAD_SYNC_TIMEOUT = 120
HEAD_SYNC_INTERVAL = 5
LOW_BUDGET = 100
RATE_LIMIT_BACKOFF = 60
RATE_LIMIT_BACKOFF_MAX = 900
RATE_LIMIT_PATTERN = re.compile(
    r"rate limit|submitted too quickly|abuse detection|secondary", re.IGNORECASE
)


class RateLimited(RuntimeError):
    pass


class ApiError(RuntimeError):
    pass


def log(line):
    print(f"{time.strftime('%H:%M:%S')} {line}", flush=True)


def gh(args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        message = result.stderr.strip() or f"gh {args[0]} failed"
        if RATE_LIMIT_PATTERN.search(message):
            raise RateLimited(message)
        raise RuntimeError(message)
    return result.stdout


def seconds_until(reset_epoch):
    return max(0.0, reset_epoch - time.time()) + 5


def primary_limit_wait():
    """Seconds until the GraphQL budget resets, or None if it is not exhausted."""
    try:
        budget = json.loads(gh(["api", "rate_limit"]))["resources"]["graphql"]
    except (RuntimeError, KeyError, TypeError, json.JSONDecodeError):
        return None
    if budget["remaining"] > 0:
        return None
    return seconds_until(budget["reset"])


def call_api(fn, retry_delay):
    """Call fn, waiting out rate limits and retrying transient failures."""
    failures = 0
    backoff = RATE_LIMIT_BACKOFF
    while True:
        try:
            return fn()
        except RateLimited as e:
            wait = primary_limit_wait()
            kind = "primary"
            if wait is None:
                wait, kind = backoff, "secondary"
                backoff = min(backoff * 2, RATE_LIMIT_BACKOFF_MAX)
            reason = str(e).splitlines()[0]
            log(f"WAIT rate_limited ({kind}) {int(wait)}s: {reason}")
            time.sleep(wait)
        except (RuntimeError, KeyError, TypeError, json.JSONDecodeError) as e:
            failures += 1
            log(f"WARN api failure {failures}/{MAX_API_FAILURES}: {e}")
            if failures >= MAX_API_FAILURES:
                raise ApiError(str(e)) from e
            time.sleep(retry_delay)


def resolve_pr(pr, repo):
    args = ["pr", "view", pr, "--json", "url"]
    if repo:
        args += ["--repo", repo]
    url = json.loads(gh(args))["url"]
    match = re.match(r"https://[^/]+/([^/]+)/([^/]+)/pull/(\d+)", url)
    if not match:
        raise RuntimeError(f"cannot parse PR URL: {url}")
    return match.group(1), match.group(2), int(match.group(3))


def fetch(owner, name, number):
    out = gh(
        [
            "api",
            "graphql",
            "-f", f"query={QUERY}",
            "-f", f"owner={owner}",
            "-f", f"name={name}",
            "-F", f"number={number}",
        ]
    )
    data = json.loads(out)["data"]
    return data["viewer"]["login"], data["repository"]["pullRequest"], data["rateLimit"]


def next_delay(interval, rate):
    """Poll interval, stretched to the budget reset when the budget is low."""
    if rate["remaining"] >= LOW_BUDGET:
        return interval
    reset = datetime.fromisoformat(rate["resetAt"].replace("Z", "+00:00"))
    wait = max(interval, seconds_until(reset.timestamp()))
    log(f"WAIT low_budget remaining={rate['remaining']} {int(wait)}s")
    return wait


def login_of(node):
    author = node.get("author") or {}
    return author.get("login") or "ghost"


def checks_of(pr):
    """Return (pending, failed, total) for the head commit's checks.

    A CANCELLED check run is ignored when another run of the same check on
    the same commit was not cancelled: it is a duplicate run superseded by
    workflow concurrency, not a failure.
    """
    nodes = pr["commits"]["nodes"]
    rollup = nodes[0]["commit"]["statusCheckRollup"] if nodes else None
    contexts = rollup["contexts"]["nodes"] if rollup else []
    live = {
        c["name"]
        for c in contexts
        if c["__typename"] == "CheckRun" and c.get("conclusion") != "CANCELLED"
    }
    pending, failed = [], []
    for c in contexts:
        if c["__typename"] == "CheckRun":
            label, url = c["name"], c.get("detailsUrl") or ""
            if c.get("conclusion") == "CANCELLED" and label in live:
                continue
            if c["status"] != "COMPLETED":
                pending.append(label)
            elif c.get("conclusion") in FAILED_CONCLUSIONS:
                failed.append((label, c["conclusion"], url))
        else:
            label, url = c["context"], c.get("targetUrl") or ""
            if c["state"] in PENDING_STATUS_STATES:
                pending.append(label)
            elif c["state"] in FAILED_STATUS_STATES:
                failed.append((label, c["state"], url))
    return pending, failed, len(contexts)


def feedback_events(pr, me, ignored, baseline_ids):
    events = []
    for t in pr["reviewThreads"]["nodes"]:
        comments = t["comments"]["nodes"]
        if t["isResolved"] or not comments:
            continue
        last = comments[-1]
        who = login_of(last)
        if who != me and who not in ignored:
            where = f"{t['path']}:{t['line']}" if t.get("line") else t["path"]
            events.append(f"review_thread {where} by {who} {last['url']}")
    for r in pr["reviews"]["nodes"]:
        who = login_of(r)
        if r["id"] in baseline_ids or who == me or who in ignored:
            continue
        if (r.get("body") or "").strip() or r["state"] == "CHANGES_REQUESTED":
            events.append(f"review {r['state']} by {who} {r['url']}")
    for c in pr["comments"]["nodes"]:
        who = login_of(c)
        if c["id"] in baseline_ids or who == me or who in ignored:
            continue
        events.append(f"comment by {who} {c['url']}")
    return events


def review_bots(pr, extra):
    bots = set(extra)
    for r in pr["reviews"]["nodes"]:
        author = r.get("author") or {}
        if author.get("__typename") == "Bot":
            bots.add(author["login"])
    return bots


def approval_state(pr, me):
    """Return APPROVED, CHANGES_REQUESTED, or PENDING.

    Uses GitHub's reviewDecision when branch protection requires reviews;
    otherwise each other reviewer's latest decisive review.
    """
    decision = pr.get("reviewDecision")
    if decision in ("APPROVED", "CHANGES_REQUESTED"):
        return decision
    if decision == "REVIEW_REQUIRED":
        return "PENDING"
    latest = {}
    for r in pr["reviews"]["nodes"]:  # oldest first
        who = login_of(r)
        if who != me and r["state"] in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[who] = r["state"]
    states = set(latest.values())
    if "CHANGES_REQUESTED" in states:
        return "CHANGES_REQUESTED"
    if "APPROVED" in states:
        return "APPROVED"
    return "PENDING"


def bots_missing(pr, bots, head):
    reviewed = {
        login_of(r)
        for r in pr["reviews"]["nodes"]
        if (r.get("commit") or {}).get("oid") == head
    }
    return sorted(bots - reviewed)


def queued(pr):
    """Whether the PR is already queued to merge (auto-merge or Graphite)."""
    if pr.get("autoMergeRequest"):
        return True
    state = False
    # Graphite's activity comment may be posted as the app or as the user.
    for c in pr["comments"]["nodes"]:
        body = c.get("body") or ""
        if "Merge activity" not in body:
            continue
        # Graphite appends to one activity comment; the latest line wins.
        for line in body.splitlines():
            if GRAPHITE_QUEUED.search(line):
                state = True
            elif GRAPHITE_DEQUEUED.search(line) or "Merged by the" in line:
                state = "Merged by the" in line
    return state


def open_prs_by(owner, name, author):
    out = gh(
        [
            "pr", "list", "--repo", f"{owner}/{name}", "--author", author,
            "--state", "open", "--limit", "100", "--json", "number",
        ]
    )
    return {item["number"] for item in json.loads(out)}


class Target:
    """Watch state of one PR."""

    def __init__(self, owner, name, number, pr):
        self.owner, self.name, self.number = owner, name, number
        self.pr = pr
        self.head = pr["headRefOid"]
        self.baseline_ids = {r["id"] for r in pr["reviews"]["nodes"]} | {
            c["id"] for c in pr["comments"]["nodes"]
        }
        self.started = time.monotonic()
        self.checks_done_at = None
        self.last_status = None
        self.stale_base_polls = 0

    def label(self):
        return f"#{self.number}"

    def evaluate(self, me, ignored, args):
        """Return (events, ready_note or None)."""
        pr, tag = self.pr, self.label()
        events = []
        if pr["headRefOid"] != self.head:
            events.append(
                f"head_changed {tag} {self.head[:10]} -> {pr['headRefOid'][:10]}"
            )
        if pr["mergeable"] == "CONFLICTING":
            events.append(f"conflict {tag} mergeStateStatus={pr['mergeStateStatus']}")
        if STALE_BASE.match(pr.get("baseRefName") or ""):
            self.stale_base_polls += 1
            if self.stale_base_polls >= STALE_BASE_POLLS:
                events.append(f"stale_base {tag} base={pr['baseRefName']}")
        else:
            self.stale_base_polls = 0
        pending, failed, total = checks_of(pr)
        for label, conclusion, url in failed:
            events.append(f"ci_failure {tag} {label} {conclusion} {url}")
        events += [
            f"{e.split(' ', 1)[0]} {tag} {e.split(' ', 1)[1]}"
            for e in feedback_events(pr, me, ignored, self.baseline_ids)
        ]
        if events:
            return events, None

        elapsed = time.monotonic() - self.started
        no_checks = total == 0 and elapsed >= args.no_checks_grace
        checks_done = no_checks or (total > 0 and not pending)
        missing = bots_missing(pr, review_bots(pr, args.bot), self.head)
        approval = approval_state(pr, me)
        approved = args.no_approval or approval == "APPROVED"
        in_queue = queued(pr)
        status = (
            f"{tag} checks={total - len(pending)}/{total} done"
            f" mergeable={pr['mergeable']} bots_missing={','.join(missing) or '-'}"
            f" approval={approval} queued={str(in_queue).lower()}"
        )
        if status != self.last_status:
            log(f"STATUS {status}")
            self.last_status = status
        if not checks_done:
            return [], None
        self.checks_done_at = self.checks_done_at or time.monotonic()
        waited = time.monotonic() - self.checks_done_at
        bots_done = not missing or waited >= args.bot_timeout
        if pr["mergeable"] == "UNKNOWN" or not bots_done or not approved:
            return [], None
        if args.until_merged and in_queue:
            return [], None
        note = f" bots_never_reviewed={','.join(missing)}" if missing else ""
        return [], (
            f"{tag} mergeStateStatus={pr['mergeStateStatus']}"
            f" approval={approval} queued={str(in_queue).lower()}{note}"
        )


def parse_heads(values, numbers):
    """--head SHA (single PR) or --head PR=SHA (any number of PRs)."""
    heads = {}
    for value in values:
        if "=" in value:
            pr, sha = value.split("=", 1)
            heads[int(pr.lstrip("#"))] = sha
        elif len(numbers) == 1:
            heads[numbers[0]] = value
        else:
            raise ValueError("with several PRs, use --head PR=SHA")
    return heads


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("prs", nargs="*", help="PR numbers, URLs, or branches")
    parser.add_argument("--repo", help="OWNER/REPO (default: current repo)")
    parser.add_argument(
        "--author",
        help="also watch every open PR by this login (\"@me\" works), and report "
        "PRs it opens while watching as EVENT new_pr",
    )
    parser.add_argument(
        "--interval", type=int, default=20, help="poll seconds (default 20)"
    )
    parser.add_argument(
        "--bot",
        action="append",
        default=[],
        help="review bot login that must review the head commit (repeatable); "
        "bots that already reviewed this PR are added automatically",
    )
    parser.add_argument(
        "--bot-timeout",
        type=int,
        default=900,
        help="seconds to wait for bot reviews after checks pass (default 900)",
    )
    parser.add_argument(
        "--no-checks-grace",
        type=int,
        default=180,
        help="seconds to wait for checks to appear before treating the PR as "
        "having none (default 180)",
    )
    parser.add_argument(
        "--no-approval",
        action="store_true",
        help="report ready without waiting for an approval",
    )
    parser.add_argument(
        "--until-merged",
        action="store_true",
        help="keep watching PRs already queued for merge instead of reporting "
        "them ready; exit 20 when one merges",
    )
    parser.add_argument(
        "--head",
        action="append",
        default=[],
        help="commit SHA you just pushed (PR=SHA with several PRs); wait until "
        "the PR reports it before judging, so a stale green head is never "
        "reported ready",
    )
    parser.add_argument(
        "--ignore-author",
        action="append",
        default=[],
        help="author login whose comments never count as feedback (repeatable; "
        "graphite-app is always ignored)",
    )
    args = parser.parse_args()
    if not args.prs and not args.author:
        parser.error("give at least one PR or --author")

    try:
        resolved = [
            call_api(lambda pr=pr: resolve_pr(pr, args.repo), args.interval)
            for pr in args.prs
        ]
        if args.author:
            if resolved:
                owner, name = resolved[0][0], resolved[0][1]
            else:
                repo = args.repo or json.loads(
                    gh(["repo", "view", "--json", "nameWithOwner"])
                )["nameWithOwner"]
                owner, name = repo.split("/", 1)
            known = call_api(
                lambda: open_prs_by(owner, name, args.author), args.interval
            )
            numbers = {n for _, _, n in resolved}
            resolved += [(owner, name, n) for n in sorted(known - numbers)]
        numbers = [n for _, _, n in resolved]
        try:
            heads = parse_heads(args.head, numbers)
        except ValueError as e:
            parser.error(str(e))

        targets = []
        me = None
        rate = None
        for owner, name, number in resolved:
            me, pr, rate = call_api(
                lambda: fetch(owner, name, number), args.interval
            )
            expected = heads.get(number)
            deadline = time.monotonic() + HEAD_SYNC_TIMEOUT
            while (
                expected
                and pr["state"] == "OPEN"
                and not pr["headRefOid"].startswith(expected)
            ):
                if time.monotonic() >= deadline:
                    log(
                        f"EVENT head_mismatch #{number} expected={expected[:10]}"
                        f" pr={pr['headRefOid'][:10]}"
                    )
                    log("RESULT action_needed events=1")
                    return EXIT_ACTION
                log(
                    f"WAIT head #{number} expected={expected[:10]}"
                    f" pr={pr['headRefOid'][:10]}"
                )
                time.sleep(HEAD_SYNC_INTERVAL)
                me, pr, rate = call_api(
                    lambda: fetch(owner, name, number), args.interval
                )
            targets.append(Target(owner, name, number, pr))
    except ApiError as e:
        log(f"RESULT api_error {e}")
        return EXIT_API
    if not targets:
        log("RESULT closed no_open_prs")
        return EXIT_CLOSED

    ignored = set(args.ignore_author) | DEFAULT_IGNORED_AUTHORS
    known = {t.number for t in targets}
    for t in targets:
        log(f"WATCH {t.pr['url']} head={t.head[:10]} as {me}")

    while True:
        events, ready, closed = [], [], []
        for t in targets:
            if t.pr["state"] != "OPEN":
                closed.append(f"{t.label()} state={t.pr['state']}")
                continue
            found, note = t.evaluate(me, ignored, args)
            events += found
            if note:
                ready.append(note)
        if closed:
            log(f"RESULT closed {' '.join(closed)}")
            return EXIT_CLOSED
        if args.author:
            t0 = targets[0]
            try:
                now_open = call_api(
                    lambda: open_prs_by(t0.owner, t0.name, args.author), args.interval
                )
            except ApiError as e:
                log(f"RESULT api_error {e}")
                return EXIT_API
            events += [f"new_pr #{n}" for n in sorted(now_open - known)]
        if events:
            for e in events:
                log(f"EVENT {e}")
            log(f"RESULT action_needed events={len(events)}")
            return EXIT_ACTION
        if ready:
            log(f"RESULT ready {' | '.join(ready)}")
            return EXIT_READY

        time.sleep(next_delay(args.interval, rate))
        try:
            for t in targets:
                _, t.pr, rate = call_api(
                    lambda t=t: fetch(t.owner, t.name, t.number), args.interval
                )
        except ApiError as e:
            log(f"RESULT api_error {e}")
            return EXIT_API


if __name__ == "__main__":
    sys.exit(main())
