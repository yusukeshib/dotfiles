#!/usr/bin/env python3
"""Watch a GitHub PR and exit as soon as something needs action.

Polls the PR with one GraphQL query per interval and exits on the first poll
that finds any of:

  - a failing check on the head commit (does not wait for other checks),
  - a merge conflict with the base branch,
  - an unresolved review thread whose latest comment is not by you,
  - a new review (with a body or CHANGES_REQUESTED) or PR comment by someone
    else, posted after the watch started,
  - the head commit changing (someone else pushed), or not reaching --head
    within 120 s.

All events found in that poll are printed, so handle every one of them.

Exit codes:
  0   ready: all checks finished green, no conflict, no new feedback, every
      review bot posted a review for the head commit (or --bot-timeout passed),
      and the PR is approved (waits indefinitely; --no-approval skips this)
  10  action needed: see the EVENT lines
  20  PR is closed or merged
  3   GitHub API kept failing (not counting rate limits)
  2   usage error

Output lines: "STATUS ..." when the state changes, "EVENT <kind> ..." for each
problem, "WAIT ..." while rate limited, and a final "RESULT ..." line.

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
        nodes { id url author { login } }
      }
    }
  }
}
"""

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
    """Return (pending, failed, total) for the head commit's checks."""
    nodes = pr["commits"]["nodes"]
    rollup = nodes[0]["commit"]["statusCheckRollup"] if nodes else None
    contexts = rollup["contexts"]["nodes"] if rollup else []
    pending, failed = [], []
    for c in contexts:
        if c["__typename"] == "CheckRun":
            label, url = c["name"], c.get("detailsUrl") or ""
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


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("pr", help="PR number, URL, or branch")
    parser.add_argument("--repo", help="OWNER/REPO (default: current repo)")
    parser.add_argument("--interval", type=int, default=20, help="poll seconds (default 20)")
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
        "--head",
        help="commit SHA you just pushed; wait until the PR reports it before "
        "judging, so a stale green head is never reported ready",
    )
    parser.add_argument(
        "--ignore-author",
        action="append",
        default=[],
        help="author login whose comments never count as feedback (repeatable)",
    )
    args = parser.parse_args()

    try:
        owner, name, number = call_api(
            lambda: resolve_pr(args.pr, args.repo), args.interval
        )
        me, pr, rate = call_api(lambda: fetch(owner, name, number), args.interval)
        deadline = time.monotonic() + HEAD_SYNC_TIMEOUT
        while (
            args.head
            and pr["state"] == "OPEN"
            and not pr["headRefOid"].startswith(args.head)
        ):
            if time.monotonic() >= deadline:
                log(
                    f"EVENT head_mismatch expected={args.head[:10]}"
                    f" pr={pr['headRefOid'][:10]}"
                )
                log("RESULT action_needed events=1")
                return EXIT_ACTION
            log(f"WAIT head expected={args.head[:10]} pr={pr['headRefOid'][:10]}")
            time.sleep(HEAD_SYNC_INTERVAL)
            me, pr, rate = call_api(lambda: fetch(owner, name, number), args.interval)
    except ApiError as e:
        log(f"RESULT api_error {e}")
        return EXIT_API

    ignored = set(args.ignore_author)
    head = pr["headRefOid"]
    baseline_ids = {r["id"] for r in pr["reviews"]["nodes"]} | {
        c["id"] for c in pr["comments"]["nodes"]
    }
    started = time.monotonic()
    checks_done_at = None
    last_status = None
    log(f"WATCH {pr['url']} head={head[:10]} as {me}")

    while True:
        if pr["state"] != "OPEN":
            log(f"RESULT closed state={pr['state']}")
            return EXIT_CLOSED

        events = []
        if pr["headRefOid"] != head:
            events.append(f"head_changed {head[:10]} -> {pr['headRefOid'][:10]}")
        if pr["mergeable"] == "CONFLICTING":
            events.append(f"conflict mergeStateStatus={pr['mergeStateStatus']}")
        pending, failed, total = checks_of(pr)
        for label, conclusion, url in failed:
            events.append(f"ci_failure {label} {conclusion} {url}")
        events += feedback_events(pr, me, ignored, baseline_ids)

        if events:
            for e in events:
                log(f"EVENT {e}")
            log(f"RESULT action_needed events={len(events)}")
            return EXIT_ACTION

        elapsed = time.monotonic() - started
        no_checks = total == 0 and elapsed >= args.no_checks_grace
        checks_done = no_checks or (total > 0 and not pending)
        bots = review_bots(pr, args.bot)
        missing = bots_missing(pr, bots, head)
        approval = approval_state(pr, me)
        approved = args.no_approval or approval == "APPROVED"

        status = (
            f"checks={total - len(pending)}/{total} done"
            f" mergeable={pr['mergeable']} bots_missing={','.join(missing) or '-'}"
            f" approval={approval}"
        )
        if status != last_status:
            log(f"STATUS {status}")
            last_status = status

        if checks_done:
            checks_done_at = checks_done_at or time.monotonic()
            waited = time.monotonic() - checks_done_at
            bots_done = not missing or waited >= args.bot_timeout
            if pr["mergeable"] != "UNKNOWN" and bots_done and approved:
                note = f" bots_never_reviewed={','.join(missing)}" if missing else ""
                log(
                    f"RESULT ready mergeStateStatus={pr['mergeStateStatus']}"
                    f" approval={approval}{note}"
                )
                return EXIT_READY

        time.sleep(next_delay(args.interval, rate))
        try:
            _, pr, rate = call_api(lambda: fetch(owner, name, number), args.interval)
        except ApiError as e:
            log(f"RESULT api_error {e}")
            return EXIT_API


if __name__ == "__main__":
    sys.exit(main())
