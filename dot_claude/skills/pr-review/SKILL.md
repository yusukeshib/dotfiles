---
name: code-review
description: Perform a comprehensive codebase review, fix ALL found issues, and create a PR with the full report
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
  - Task
  - TaskCreate
  - TaskUpdate
  - TaskList
---

# Code Review Skill

Perform a comprehensive code review of the entire codebase. Thoroughly review each module/package one by one, then review the whole architecture holistically. Fix ALL issues found — High, Medium, and Low priority. Then create a PR with the complete review report.

## Workflow

### Phase 1: Automated Checks

Detect the project's toolchain and run whatever formatters, linters, type checkers, and build/compile checks the project uses. Common examples:

- **Rust**: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo check --workspace`
- **JavaScript/TypeScript**: `prettier --check .`, `eslint .`, `tsc --noEmit`
- **Python**: `ruff check .`, `ruff format --check .`, `mypy .`
- **Go**: `gofmt -l .`, `go vet ./...`, `go build ./...`
- **Other**: whatever is configured in the project's CI, `Makefile`, `package.json` scripts, `pyproject.toml`, etc.

Inspect the repo (README, CI config, package manifests) to discover which checks apply, then run them and record findings.

### Phase 2: Thorough Per-Module Review

Identify the project's top-level units of organization (crates, packages, modules, apps, services, libraries) and review **every one of them, one by one**. Do NOT skim or skip — spend real time in each. Use Agent subagents to review multiple units in parallel where possible for efficiency.

Work in dependency order where it exists (leaf dependencies first, then consumers). For each unit, read through the source files and evaluate against the review categories below.

**Review categories for each unit:**

1. **Error Handling** — Unhandled fallible operations (unwraps, ignored errors, swallowed exceptions), missing propagation, panic/crash paths in library code
2. **Unsafe / FFI Code** — Any unsafe blocks, raw pointer usage, FFI boundary issues, memory-safety concerns
3. **Resource Management** — Leaks, missing cleanup, unbounded caches/buffers, lock contention, file/socket/handle lifecycle
4. **Performance** — Unnecessary allocations, redundant copies/clones, O(n²) patterns where better exists, missing streaming/iteration, N+1 queries
5. **Language Idioms** — Non-idiomatic patterns for the language in use, missing standard abstractions, improper use of built-in types
6. **Project Conventions** — Violations of documented conventions (CLAUDE.md, CONTRIBUTING.md, style guides, architectural decision records)
7. **Security** — Injection (command/SQL/path), unvalidated input at trust boundaries, secrets in code, unsafe deserialization, authz/authn gaps
8. **Dead Code** — Unused functions, unreachable branches, stale imports, commented-out code
9. **Test Coverage Gaps** — Critical logic paths with no tests, missing edge-case coverage, brittle or tautological tests

### Phase 3: Whole-Architecture Review

After reviewing individual units, step back and review the architecture holistically. Evaluate:

1. **Dependency Graph** — Are module/package dependencies clean and minimal? Any unnecessary coupling, circular, or near-circular dependency patterns?
2. **Interface / Trait Design** — Are key interfaces, traits, or abstract base classes well-designed? Are boundaries in the right places? Missing or leaky abstractions?
3. **Data Flow** — Is the pipeline of data through the system clean? Any unnecessary intermediate representations or redundant transformations?
4. **Error Propagation Across Boundaries** — Do errors flow cleanly across module boundaries? Are error types well-composed? Anywhere errors are swallowed or lose context?
5. **Platform / Environment Abstraction** — If the code targets multiple platforms or environments, is the split clean? Are conditional compilation / feature flags / environment checks well-organized or scattered?
6. **API Surface** — Are public APIs minimal and well-documented? Any internal details accidentally exposed?
7. **Consistency** — Are patterns consistent across units (error handling, naming, module organization, logging)? Any unit that diverges without good reason?
8. **Scalability & Extensibility** — Would adding a new feature, backend, or integration be straightforward? Any architectural bottlenecks?

### Phase 4: Compile Findings

Categorize every finding by priority:

- **High** — Panics/crashes in library code, unsafe misuse, security vulnerabilities, data corruption risks, architectural flaws that block correctness
- **Medium** — Performance issues, non-idiomatic patterns, architecture concerns, missing error handling at boundaries, interface design issues
- **Low** — Dead code, cosmetic issues, minor style inconsistencies, minor API surface issues

### Phase 5: Fix Issues

**Goal: fix every issue found.** "Higher effort" or "requires changing signatures" is NOT a valid reason to skip. The only valid reasons to defer a fix are:

- The fix requires runtime dependencies not available in this environment (e.g., GPU hardware, system libraries, proprietary SDKs)
- The fix requires platform-specific testing that cannot be verified here (e.g., iOS/Android devices, specific OS versions, hardware peripherals)

For each issue category, apply the appropriate fix strategy:

| Issue type | Fix strategy |
|---|---|
| Unhandled fallible calls in library code | Propagate errors properly using the language's idiomatic mechanism; update signatures through the call chain as needed |
| Dead code | Remove it (and any suppression annotations like `#[allow(dead_code)]`, `// eslint-disable`, `# noqa`) |
| Silent error swallowing / ignored results | Log via the project's logger before falling back, or propagate the error |
| Non-idiomatic patterns | Refactor to idiomatic style for the language |
| Unnecessary copies / allocations | Use references, views, borrows, or in-place mutation as appropriate |
| Convention violations | Fix to match documented project conventions |
| Test coverage gaps | Write unit/integration tests for the uncovered logic |
| Duplicate code | Extract shared logic into a helper/utility |

**Workflow:**

1. Create a new branch: `code-review/YYYY-MM-DD` (using today's date)
2. Fix all **High** priority issues first
3. Fix all **Medium** priority issues
4. Fix all **Low** priority issues
5. Use Agent subagents to fix independent issues in parallel where possible for efficiency
6. After fixes, re-run the project's automated checks from Phase 1, plus the test suite (e.g. `cargo test`, `npm test`, `pytest`, `go test ./...`). All must pass.
7. If any tests fail, debug and fix them before proceeding

### Phase 6: Create PR

Create a PR with:

- Title: `code-review: fix issues found in YYYY-MM-DD review`
- Body: The complete review report formatted as:

```markdown
## Code Review Report — YYYY-MM-DD

### Summary
[Brief overview of findings count by priority and by module/package]

### Architecture Review
[Key architectural findings — dependency issues, interface design, data flow, platform abstraction, consistency]

### Per-Module Findings

#### <module/package name>
[Findings for this unit with file:line references]

#### <next module/package name>
[Findings for this unit...]

... (one section per unit reviewed)

### High Priority (Fixed)
[List each finding with file:line, description, and what was fixed]

### Medium Priority (Fixed)
[List each finding with file:line, description, and what was fixed]

### Low Priority (Fixed)
[List each finding with file:line, description, and what was fixed]

### Deferred (Environment Limitation)
[Only list findings that genuinely cannot be fixed or verified due to missing runtime dependencies or platform-specific testing. Explain the specific blocker for each.]

### Automated Check Results
[Output from the project's formatters, linters, type checkers, and build/test commands]
```
