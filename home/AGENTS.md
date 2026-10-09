# AGENTS.md

Shared guidance for coding agents working under `$HOME`.

## Scope and safety

- Prefer the most correct implementation, not the smallest diff. Address root
  causes rather than patching symptoms; prioritize correctness, coherent design,
  and maintainability. Refactor existing code when needed instead of preserving
  a flawed design to keep changes small. Avoid unrelated changes and speculative
  abstractions, but do not use scope control to justify an incomplete fix.
- Inside `~/.box/workspaces/<work-id>/<repo>`, keep all task work in that workspace.
  Use a sibling repo or `box repo add <repo> --workspace <work-id>`; never switch to
  another checkout. Confirm the target repo and worktree with `pwd` and
  `git status --short --branch`; recheck before committing or pushing. Never
  include unrelated changes in commits.
- Home configuration may be symlinked into `~/dotfiles`. Check the link target
  and follow that repository's `AGENTS.md` for managed files.
- Routine history updates on your task branch need no separate approval; use
  `--force-with-lease` rather than `--force`. Confirm before overwriting others'
  work or shared history, deleting user/shared data, or changing visibility beyond
  the request. Routine removal of task-owned files is fine.
- Start searches in relevant locations and expand as needed. Do not trawl unrelated
  directories, credentials, caches, or session logs to work around a missing
  command or integration. Report blockers rather than searching indiscriminately.

## Implementation and validation

- **Highest-priority workflow: plan(high) -> work(low).** Explicitly switch to
  `high` for planning and design decisions, then to `low` before implementation.
  Do not modify product files during planning. If implementation invalidates the
  plan or exposes an unresolved design decision, stop work, return to `high` to
  revise the plan, then resume at `low`. Routine, well-scoped work can start
  directly at `low` without a plan file.
- For large, high-risk, or multi-session work, save a temporary plan covering
  changes, invariants, validation, and rollback. Minor unknowns or thinking-level
  changes alone do not require a plan file. Delete the temporary plan when done.
- Ask before materially changing the agreed goal, external impact, or cost, and
  clarify consequential ambiguities in user intent. Necessary refactoring for
  the agreed goal is not by itself scope expansion requiring approval.
- Run targeted checks first, then broader validation appropriate to the change.
  Normal local tests need no separate approval. For substantial model-backed
  evaluations, state case/call count, expected runtime/cost, and pass/fail criteria.
  Get approval for expensive, long-running, or externally consequential validation
  beyond the agreed scope; small checks need no ceremonial preamble.
- Report what was implemented, what was actually verified, and what remains
  unverified. Do not present implementation or limited tests as broader proof.
- Use advisor for concrete unresolved decisions, repeated failures, specific
  high-risk concerns, or explicit requests—not routine approval. Verify its
  suggestions against the code and user goal.

## Git and task completion

- Prefer independent PRs from the base branch. Stack only for a real dependency
  and with user approval. Do not start CI watchers unless explicitly requested.
- After completing and validating repository changes, commit and push task-owned
  files unless told not to. If unsafe or unsuccessful, report the blocker.
- For PR feedback, track each thread through fix, validation, commit, and push.
  Then reply where useful, resolve only addressed threads, and re-fetch to verify
  resolution. Report anything still open or unverifiable.
- For a running `goal` or bot goal, begin with `goal list` and inspect the listed
  files and status. Use that configuration, not similarly named or retired systems.

## Connected services

- Use connected services' MCP tools first. Discover deferred tools before assuming
  they are unavailable; use their actual schemas and required workflow guides.
- Read requests are read-only. Search narrowly, paginate as needed, and cite source
  links or record IDs. Distinguish no results from access failures or incomplete
  retrieval. If blocked, report it and request access or content; do not substitute
  local searches, browser automation, or guessed CLI commands.

## Agent tools

- Use `openai-codex/gpt-6.1-sol`. Instruct every pi implementation subagent to call
  `set_thinking_level({"level":"low"})` before work and report the effective level;
  do not assume it inherits the parent's level. If blocked by a design issue,
  have it stop and return to the parent for replanning at `high`, not improvise
  beyond the plan at `low`. Use the provider-qualified name for model overrides.
- At the plan-to-work handoff, if reported context usage is 65% or higher, save
  the plan, decisions, exact state needed for implementation, and next action;
  then compact and begin work at `low`. Below 65%, switch directly to `low`
  without compacting. If context usage is unavailable, do not guess it. Never
  compact solely to change thinking level; provide a concrete continuation.
- In pi, use `babysit_run` for commands lasting more than a few seconds; no legacy
  `process`, `&`, or `nohup`. Name sessions clearly. After a background start, wait
  for notification instead of polling; use `continueAfterStart` only for immediate,
  specific work. Collect every delegated subagent's result before finishing.
- Prefer `rg` for content searches and `fd` for file discovery. Use alternatives
  when unavailable; keep searches scoped regardless of the tool.
