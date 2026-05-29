// pr-helper: GitHub PR comment & review helper for pi.
//
// Provides:
//   Tools (LLM-callable):
//     - pr_comments_list      List unresolved review threads + PR comments
//     - pr_comment_reply      Reply to a specific review thread
//     - pr_thread_resolve     Resolve a review thread
//     - pr_post_comment       Post a new top-level PR (issue) comment
//   Commands (user-typed):
//     - /pr-diff [num]        Show diff with `delta` syntax highlighting
//     - /pr-comments [num]    Print formatted comments
//
// Requires: gh (authenticated), optionally delta.
// Write operations skip ctx.ui.confirm() — auto-confirmed by default,
// so skill-driven PR-feedback loops can batch many resolves/replies
// without per-call confirmation prompts.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// ───────────────────────── helpers ─────────────────────────

async function sh(
	pi: ExtensionAPI,
	cmd: string,
	args: string[],
	opts: { cwd?: string; input?: string; timeout?: number } = {},
): Promise<{ ok: boolean; stdout: string; stderr: string; code: number }> {
	const res = await pi.exec(cmd, args, {
		cwd: opts.cwd,
		input: opts.input,
		timeout: opts.timeout ?? 30_000,
	});
	return { ok: res.code === 0, stdout: res.stdout, stderr: res.stderr, code: res.code };
}

async function resolvePr(pi: ExtensionAPI, cwd: string, explicit?: number): Promise<number | null> {
	if (explicit && Number.isFinite(explicit) && explicit > 0) return explicit;
	const r = await sh(pi, "gh", ["pr", "view", "--json", "number", "-q", ".number"], { cwd });
	if (!r.ok) return null;
	const n = Number.parseInt(r.stdout.trim(), 10);
	return Number.isFinite(n) ? n : null;
}

async function repoNwo(pi: ExtensionAPI, cwd: string): Promise<{ owner: string; name: string } | null> {
	const r = await sh(pi, "gh", ["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"], { cwd });
	if (!r.ok) return null;
	const [owner, name] = r.stdout.trim().split("/");
	if (!owner || !name) return null;
	return { owner, name };
}

type ReviewThread = {
	id: string;
	isResolved: boolean;
	isOutdated: boolean;
	path: string;
	line: number | null;
	comments: { author: string; body: string; createdAt: string; url: string }[];
};

async function fetchThreads(
	pi: ExtensionAPI,
	cwd: string,
	pr: number,
	owner: string,
	name: string,
	onlyUnresolved = true,
): Promise<ReviewThread[]> {
	const query = `
    query($owner:String!,$name:String!,$pr:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$pr){
          reviewThreads(first:100){
            nodes{
              id isResolved isOutdated path line
              comments(first:50){
                nodes{ author{login} bodyText createdAt url }
              }
            }
          }
        }
      }
    }`;
	const r = await sh(
		pi,
		"gh",
		[
			"api",
			"graphql",
			"-f",
			`query=${query}`,
			"-F",
			`owner=${owner}`,
			"-F",
			`name=${name}`,
			"-F",
			`pr=${pr}`,
		],
		{ cwd },
	);
	if (!r.ok) throw new Error(`gh api graphql failed: ${r.stderr || r.stdout}`);
	const data = JSON.parse(r.stdout);
	const nodes = data?.data?.repository?.pullRequest?.reviewThreads?.nodes ?? [];
	return nodes
		.filter((n: { isResolved: boolean }) => (onlyUnresolved ? !n.isResolved : true))
		.map(
			(n: {
				id: string;
				isResolved: boolean;
				isOutdated: boolean;
				path: string;
				line: number | null;
				comments: {
					nodes: { author: { login: string }; bodyText: string; createdAt: string; url: string }[];
				};
			}): ReviewThread => ({
				id: n.id,
				isResolved: n.isResolved,
				isOutdated: n.isOutdated,
				path: n.path,
				line: n.line,
				comments: n.comments.nodes.map((c) => ({
					author: c.author?.login ?? "unknown",
					body: c.bodyText,
					createdAt: c.createdAt,
					url: c.url,
				})),
			}),
		);
}

// ANSI color helpers (pi-tui's Text preserves ANSI escape codes).
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const CYAN = "\x1b[36m";
const YELLOW = "\x1b[33m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const MAGENTA = "\x1b[35m";
const BLUE = "\x1b[34m";
const c = (color: string, s: string) => `${color}${s}${RESET}`;

function formatThreads(threads: ReviewThread[]): string {
	if (threads.length === 0) return c(DIM, "(no review threads)");
	return threads
		.map((t, i) => {
			const idx = c(BOLD + YELLOW, `[${i + 1}]`);
			const loc = c(BOLD + CYAN, `${t.path}:${t.line ?? "?"}`);
			const tid = c(DIM, `thread=${t.id}`);
			const flags = [
				t.isOutdated ? c(MAGENTA, "(outdated)") : "",
				t.isResolved ? c(GREEN, "(resolved)") : c(RED, "(unresolved)"),
			]
				.filter(Boolean)
				.join(" ");
			const head = `${idx} ${loc}  ${tid}  ${flags}`;
			const body = t.comments
				.map((cm) => {
					const who = c(BOLD + GREEN, `@${cm.author}`);
					const when = c(DIM, cm.createdAt);
					const text = cm.body.replace(/\n/g, "\n      ");
					return `    ${who} ${when}\n      ${text}`;
				})
				.join("\n");
			return `${head}\n${body}`;
		})
		.join("\n\n");
}

function formatHeader(pr: number, owner: string, name: string): string {
	return c(BOLD + BLUE, `PR #${pr}`) + "  " + c(DIM, `${owner}/${name}`);
}

// ───────────────────────── extension ─────────────────────────

export default function (pi: ExtensionAPI) {
	// ── Renderer for pr-helper messages ────────────────────
	pi.registerMessageRenderer("pr-helper", (message, { expanded }, theme) => {
		const MAX_COLLAPSED = 40;
		const content = String(message.content ?? "");
		const lines = content.split("\n");
		const clipped = !expanded && lines.length > MAX_COLLAPSED;
		const shown = clipped ? lines.slice(0, MAX_COLLAPSED).join("\n") : content;
		const footer = clipped
			? `\n${theme.fg("dim", `… ${lines.length - MAX_COLLAPSED} more lines (Ctrl+O to expand)`)}`
			: "";
		// No background, no padding: keep delta's ANSI styling clean and preserve
		// column alignment from `delta --width=<cols>`.
		const box = new Box(0, 0);
		box.addChild(new Text(shown + footer, 0, 0));
		return box;
	});

	// ── Tool: list comments ────────────────────────────────
	pi.registerTool({
		name: "pr_comments_list",
		label: "PR Comments",
		description:
			"List review threads and comments on a GitHub Pull Request. Returns thread IDs needed for pr_comment_reply / pr_thread_resolve.",
		promptSnippet: "List GitHub PR review threads and comments (pr_comments_list)",
		parameters: Type.Object({
			pr: Type.Optional(
				Type.Number({ description: "PR number. Omit to use current branch's PR." }),
			),
			onlyUnresolved: Type.Optional(
				Type.Boolean({ description: "Only unresolved threads (default true)" }),
			),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const pr = await resolvePr(pi, ctx.cwd, params.pr);
			if (!pr) return { content: [{ type: "text", text: "Could not determine PR number." }], isError: true };
			const nwo = await repoNwo(pi, ctx.cwd);
			if (!nwo) return { content: [{ type: "text", text: "Not a GitHub repo." }], isError: true };
			const threads = await fetchThreads(pi, ctx.cwd, pr, nwo.owner, nwo.name, params.onlyUnresolved ?? true);
			return {
				content: [
					{
						type: "text",
						text: `PR #${pr} (${nwo.owner}/${nwo.name})\n\n${formatThreads(threads).replace(/\x1b\[[0-9;]*m/g, "")}`,
					},
				],
				details: { pr, threads },
			};
		},
	});

	// ── Tool: reply to a review thread ─────────────────────
	pi.registerTool({
		name: "pr_comment_reply",
		label: "Reply to PR Thread",
		description:
			"Reply to a review thread on a GitHub PR. The threadId must come from pr_comments_list. Prompts the user to confirm before posting.",
		promptSnippet: "Reply to a GitHub PR review thread (pr_comment_reply)",
		promptGuidelines: [
			"Before calling pr_comment_reply, always call pr_comments_list to obtain valid thread IDs.",
			"Show the user the draft body before calling pr_comment_reply; the tool itself also asks for confirmation.",
		],
		parameters: Type.Object({
			threadId: Type.String({ description: "Review thread node ID (from pr_comments_list)" }),
			body: Type.String({ description: "Markdown body of the reply" }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {

			const mutation = `
        mutation($threadId:ID!,$body:String!){
          addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId,body:$body}){
            comment{ url }
          }
        }`;
			const r = await sh(
				pi,
				"gh",
				[
					"api",
					"graphql",
					"-f",
					`query=${mutation}`,
					"-F",
					`threadId=${params.threadId}`,
					"-F",
					`body=${params.body}`,
				],
				{ cwd: ctx.cwd },
			);
			if (!r.ok) return { content: [{ type: "text", text: `Failed: ${r.stderr}` }], isError: true };
			const data = JSON.parse(r.stdout);
			const url = data?.data?.addPullRequestReviewThreadReply?.comment?.url ?? "(no url)";
			ctx.ui.notify("Reply posted", "info");
			return { content: [{ type: "text", text: `Posted: ${url}` }], details: { url } };
		},
	});

	// ── Tool: resolve thread ───────────────────────────────
	pi.registerTool({
		name: "pr_thread_resolve",
		label: "Resolve PR Thread",
		description: "Mark a PR review thread as resolved. Asks the user to confirm.",
		parameters: Type.Object({
			threadId: Type.String(),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const mutation = `
        mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }`;
			const r = await sh(
				pi,
				"gh",
				["api", "graphql", "-f", `query=${mutation}`, "-F", `id=${params.threadId}`],
				{ cwd: ctx.cwd },
			);
			if (!r.ok) return { content: [{ type: "text", text: `Failed: ${r.stderr}` }], isError: true };
			ctx.ui.notify("Thread resolved", "info");
			return { content: [{ type: "text", text: "Resolved." }] };
		},
	});

	// ── Tool: post top-level (issue) comment ───────────────
	pi.registerTool({
		name: "pr_post_comment",
		label: "Post PR Comment",
		description: "Post a new top-level comment to a GitHub PR's conversation tab. Asks for confirmation.",
		parameters: Type.Object({
			pr: Type.Optional(Type.Number()),
			body: Type.String(),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const pr = await resolvePr(pi, ctx.cwd, params.pr);
			if (!pr) return { content: [{ type: "text", text: "Could not determine PR number." }], isError: true };

			const r = await sh(pi, "gh", ["pr", "comment", String(pr), "--body", params.body], {
				cwd: ctx.cwd,
			});
			if (!r.ok) return { content: [{ type: "text", text: `Failed: ${r.stderr}` }], isError: true };
			ctx.ui.notify("Comment posted", "info");
			return { content: [{ type: "text", text: r.stdout.trim() || "Posted." }] };
		},
	});

	// ── Command: /pr-diff [num] ────────────────────────────
	pi.registerCommand("pr-diff", {
		description: "Show a GitHub PR diff with syntax highlighting",
		handler: async (args, ctx) => {
			const pr = await resolvePr(pi, ctx.cwd, args ? Number.parseInt(args.trim(), 10) : undefined);
			if (!pr) {
				ctx.ui.notify("No PR found", "error");
				return;
			}
			// Run gh | delta as a single shell pipeline so delta gets a real pipe stdin
			// and we can force color output via CLICOLOR_FORCE/FORCE_COLOR (delta and bat
			// honor these; otherwise they auto-disable color on non-TTY stdout).
			// Use a width slightly narrower than the TUI so wrapping never breaks
			// delta's per-line layout. Unified (non side-by-side) renders far better
			// inside the pi message area than --side-by-side.
			const raw = process.stdout.columns || Number.parseInt(process.env.COLUMNS ?? "160", 10) || 160;
			const cols = Math.max(80, raw - 4);
			const script = [
				`export CLICOLOR_FORCE=1 FORCE_COLOR=1 COLORTERM=truecolor TERM="\${TERM:-xterm-256color}"`,
				`if command -v delta >/dev/null 2>&1; then`,
				`  gh pr diff ${pr} | delta \\
    --no-gitconfig \\
    --paging=never \\
    --width=${cols} \\
    --true-color=always \\
    --line-numbers \\
    --hunk-header-decoration-style="omit" \\
    --file-decoration-style="blue ol ul" \\
    --file-style="bold blue"`,
				`else`,
				`  gh pr diff ${pr}`,
				`fi`,
			].join("\n");
			const rendered = await sh(pi, "sh", ["-c", script], { cwd: ctx.cwd, timeout: 60_000 });
			if (!rendered.ok) {
				ctx.ui.notify(`pr diff failed: ${rendered.stderr || rendered.stdout}`, "error");
				return;
			}
			const text = rendered.stdout;
			pi.sendMessage({
				customType: "pr-helper",
				content: `PR #${pr} diff:\n\n${text}`,
				display: true,
			});
		},
	});

	// ── Command: /pr-comments [num] ────────────────────────
	pi.registerCommand("pr-comments", {
		description: "Show review threads and comments on a GitHub PR",
		handler: async (args, ctx) => {
			const pr = await resolvePr(pi, ctx.cwd, args ? Number.parseInt(args.trim(), 10) : undefined);
			if (!pr) {
				ctx.ui.notify("No PR found", "error");
				return;
			}
			const nwo = await repoNwo(pi, ctx.cwd);
			if (!nwo) {
				ctx.ui.notify("Not a GitHub repo", "error");
				return;
			}
			const threads = await fetchThreads(pi, ctx.cwd, pr, nwo.owner, nwo.name, false);
			const text = `${formatHeader(pr, nwo.owner, nwo.name)}\n\n${formatThreads(threads)}`;
			pi.sendMessage({ customType: "pr-helper", content: text, display: true });
		},
	});
}