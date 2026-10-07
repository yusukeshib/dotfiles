# AGENTS.md

Shared guidance for coding agents working under `$HOME`.

## Agent workflow

- When the user refers to a running `goal` or bot goal, begin with `goal list`
  (use `--output json` when useful) and inspect the listed goal's files and
  status. Use the listed configuration as the source of truth; do not infer the
  runtime from similarly named or retired systems.
- Bound command discovery to `command -v` and explicitly relevant directories,
  with a 10-second timeout. Do not search all of `$HOME`, caches, or session
  logs to locate a missing command. Report the blocker promptly instead.
- Inside `~/.box/workspaces/<work-id>/<repo>`, keep all task work in that
  workspace. Use an existing sibling repo there, or add a missing one with
  `box repo add <repo> --workspace <work-id>`; do not switch to another checkout
  elsewhere in `$HOME`. Before editing, committing, or pushing, verify `pwd` and
  `git status --short --branch`.
- Prefer independent PRs from the base branch. Use stacked PRs only for a real
  dependency, explain it, and get user approval first.
- After completing and validating repository changes, always commit and push the
  task-owned files unless the user explicitly says not to. Never include unrelated
  worktree changes; if commit or push is unsafe or fails, report the blocker.
- Do not start CI watchers such as `gh pr checks --watch` unless continuous
  monitoring is explicitly requested.
- When addressing PR review feedback, track each review thread through the
  code change, validation, commit, and push. After the fix is pushed, reply
  where useful and resolve each thread that was actually addressed. Re-fetch
  the PR threads and confirm those threads are resolved before reporting the
  feedback task complete. Do not resolve threads whose concerns remain open;
  explicitly report any thread that cannot be resolved or verified.

### Scope, progress, and advisor use

- Prefer the smallest working end-to-end implementation using existing
  components. Do not build general frameworks merely to establish confidence.
- Separate implementation, validation, and proof status. Missing proof must
  be reported honestly; it does not automatically justify new runtime machinery
  or permission to bypass required validation.
- Measure progress by working user-visible behavior, not plans, infrastructure,
  test counts, commits, or advisor approval.
- If successive checkpoints add prerequisites without advancing working
  behavior, stop implementation, reassess the approach, and propose what to
  remove or simplify. Do not keep extending the prerequisite chain.
- Consult advisor only for a concrete unresolved decision, repeated failure,
  a specific high-risk concern, or an explicit user request—not routinely at
  task start or completion. State the question before consulting.
- Treat advisor output as hypotheses, not instructions or approval. Ask what
  can be removed and whether the current approach is wrong. Verify suggestions
  against code and the user's actual goal; reject unnecessary scope expansion.

### Planning, compaction, and thinking level

- Use `openai-codex/gpt-6.1-sol`. `low` is normal for routine, well-scoped work:
  proceed without a plan. For ambiguity, complex reasoning, architecture,
  high-risk decisions, or broad final review, call `set_thinking_level` with
  `high` before planning or continuing. Do not modify product files during a
  distinct planning phase.
- Create a plan file only when unresolved design decisions or significant risks
  warrant one, not merely because a task has multiple steps. For routine commit,
  push, PR creation, or synchronization using an established procedure, when the
  request and target are clear, perform the necessary checks and execute without
  a plan file. External writes alone do not make a task risky. Separately confirm
  authorization for force pushes, history overwrites, irreversible data deletion,
  or visibility changes. Routine deletion of task-owned files does not require
  separate confirmation; these checks do not automatically require a plan file.
- For substantial architectural, cross-cutting, production-wiring, or risky
  work that meets the planning criteria above, write an executable temporary
  plan at `high`: affected files, changes,
  invariants, failure/cancellation behavior where relevant, validation, and
  rollback. Pause for human review when ambiguous, preference-sensitive,
  destructive, expensive, or otherwise high-risk. After any required review,
  implement at `low` against the plan; delete the temporary plan when finished.
- If scope expands materially (e.g. a local edit reaches shared behavior,
  deployment, telemetry, or eval infrastructure), stop, switch to `high`, and
  present an updated impact/validation/rollback plan for human review. Earlier
  approval does not cover expanded scope or unresolved design choices.
- Before broad or model-backed validation, state case/model-call count, expected
  runtime and cost, and the pass/fail decision. Prefer targeted checks, then a
  bounded smoke panel; run a full suite only with explicit scope/cost approval.
  Do not claim targeted evals establish broad safety.
- Compact only when it adds value. Save exact state to a temporary note if
  needed (do not commit it unless permanent documentation); call
  `compact_context` alone with preservation instructions and a continuation.
  Skip compaction for short tasks; request manual compaction if the tool is
  unavailable. Thinking-level changes can rebill context: avoid repeated
  switches, prefer a natural handoff, and never compact solely to switch levels.
- For every pi subagent worker, explicitly instruct it in the task to call
  `set_thinking_level({"level":"low"})` before doing work and report the
  effective level. Do not assume it inherits `low` from the parent; the parent
  may be planning at `high`.
- If implementation invalidates the plan or a worker cannot resolve a blocker
  within it, stop the worker's implementation and return to the parent in
  plan-revision mode at `high`. Consult advisor for a concrete unresolved
  decision when useful, verify its suggestions, revise the plan (and obtain
  human review if scope expanded), then resume implementation with a worker
  explicitly set to `low`. Do not push through an obsolete plan at `low`.
- When overriding a pi subagent model, use the provider-qualified
  `openai-codex/gpt-6.1-sol` to avoid an unauthenticated provider.

## MCP and connected services

- For requests to read or search Slack, Linear, Mixpanel, Notion, Datadog,
  Braintrust, or another connected service, use that service's MCP tools first.
  Do not substitute local file searches, browser automation, or guessed CLI
  commands for the connected service.
- Codemode is disabled in this setup. Discover and call direct MCP tools; do
  not use codemode scripts or try to enable, install, or configure codemode.
  The tools actually available in the current session are the source of truth.
  If a session exposes only a codemode route, report the mismatch rather than
  silently changing configuration.
- MCP tools may be deferred rather than listed initially. When `tool_search`
  is available, search for the service and the specific operation (for example,
  `Slack search messages`, `Linear get issue`, or `Mixpanel query report`),
  then call the discovered tool using its actual schema. Do not guess tool
  names or arguments, or assume an integration is missing before discovery.
- Read any required service-specific workflow guide or resource before using
  the related tools. Follow the discovered tool's requirements for identifiers,
  query syntax, time ranges, and pagination.
- For read requests, use read-only operations. Search narrowly, fetch relevant
  records or threads, and paginate as needed. Do not send messages, modify
  issues, or change reports or settings unless the user requested those writes.
- Ground answers in retrieved results and include source links or record IDs
  when available. Distinguish no matching results from failed access, missing
  permissions, unavailable tools, and incomplete pagination.
- If discovery or a service call fails, report the specific blocker promptly.
  Do not search `$HOME`, caches, credentials, or session logs for a workaround.
  Ask for the integration to be made available or for the relevant content;
  do not claim to have read the service when retrieval did not succeed.

## Commands and processes

Use the `process` tool for builds, tests, servers, watchers, or other commands
lasting more than a few seconds; never use Bash backgrounding (`&`, `nohup`).
Name processes descriptively. After starting one without `continueAfterStart`,
wait for its automatic completion notification; never poll or sleep. Use
`continueAfterStart=true` only for immediate, specific, non-polling work.
Inspect output when needed; kill and clear finished long-lived sessions. Use
Bash only for quick observations such as `pwd`, `git status`, or a small listing.

Prefer modern CLI tools: `rg` over recursive grep, scoped `fd` over `find`, and
`sd` over `sed -i`. Never run an unscoped `find /` or high-level `find .`; fall
back to legacy tools only when necessary.
