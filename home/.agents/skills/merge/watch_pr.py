#!/usr/bin/env python3
"""Watch a GitHub PR and exit as soon as something needs action.

Polls the PR with one GraphQL query per interval and exits on the first poll
that finds any of:

  - a failing check on the head commit (does not wait for other checks),
  - a merge conflict with the base branch,
  - an unresolved review thread whose latest comment is not by you,
  - a new review (with a body or CHANGES_REQUESTED) or PR comment by someone
    else, posted after the watch started,
  - the head commit changing (someone else pushed).

All events found in that poll are printed, so handle every one of them.

Exit codes:
  0   ready: all checks finished green, no conflict, no new feedback, and every
      review bot posted a review for the head commit (or --bot-timeout passed)
  10  action needed: see the EVENT lines
  20  PR is closed or merged
  3   GitHub API kept failing
  2   usage error

Output lines: "STATUS ..." when the state changes, "EVENT <kind> ..." for each
problem, and a final "RESULT ..." line.
"""

import argparse
import json
import re
import subprocess
import sys
import time

QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
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


def log(line):
    print(f"{time.strftime('%H:%M:%S')} {line}", flush=True)


def gh(args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"gh {args[0]} failed")
    return result.stdout


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
    return data["viewer"]["login"], data["repository"]["pullRequest"]


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
        "--ignore-author",
        action="append",
        default=[],
        help="author login whose comments never count as feedback (repeatable)",
    )
    args = parser.parse_args()

    try:
        owner, name, number = resolve_pr(args.pr, args.repo)
        me, pr = fetch(owner, name, number)
    except RuntimeError as e:
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
    api_failures = 0
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

        status = (
            f"checks={total - len(pending)}/{total} done"
            f" mergeable={pr['mergeable']} bots_missing={','.join(missing) or '-'}"
        )
        if status != last_status:
            log(f"STATUS {status}")
            last_status = status

        if checks_done:
            checks_done_at = checks_done_at or time.monotonic()
            waited = time.monotonic() - checks_done_at
            if pr["mergeable"] != "UNKNOWN" and (not missing or waited >= args.bot_timeout):
                note = f" bots_never_reviewed={','.join(missing)}" if missing else ""
                log(
                    f"RESULT ready mergeStateStatus={pr['mergeStateStatus']}"
                    f" reviewDecision={pr['reviewDecision']}{note}"
                )
                return EXIT_READY

        time.sleep(args.interval)
        try:
            _, pr = fetch(owner, name, number)
            api_failures = 0
        except (RuntimeError, KeyError, TypeError, json.JSONDecodeError) as e:
            api_failures += 1
            log(f"WARN api failure {api_failures}/5: {e}")
            if api_failures >= 5:
                log("RESULT api_error")
                return EXIT_API


if __name__ == "__main__":
    sys.exit(main())
