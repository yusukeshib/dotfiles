/**
 * bash-timeout — auto-inject an LLM-estimated timeout into every `bash` tool call.
 *
 * Problem: pi's built-in bash tool supports a `timeout` (seconds) and kills the
 * process when it expires, but the LLM frequently forgets to set it. Long-running
 * or hung commands (servers, broken curls, `pnpm install` in a dead network, etc.)
 * then block the whole agent.
 *
 * This extension intercepts `tool_call` for `bash` and, when no timeout is set,
 * asks the current model to estimate a reasonable per-command timeout based on
 * the command string. The estimate is clamped to [MIN_TIMEOUT, MAX_TIMEOUT] and
 * written into `event.input.timeout`, so pi's built-in bash will SIGKILL the
 * process if it overruns.
 *
 * Behavior:
 *   - If the LLM already supplied a timeout, it's respected (only clamped to MAX).
 *   - Trivially-fast commands match a fast-path heuristic and skip the LLM call
 *     to avoid added latency on `ls`, `pwd`, `cat`, `git status`, etc.
 *   - LLM call uses the active model; on failure or non-numeric output, falls
 *     back to DEFAULT_TIMEOUT.
 *   - Estimates are cached per exact command string for the session.
 *
 * Install: drop into ~/.pi/agent/extensions/  (auto-discovered).
 * Toggle with /reload after edits.
 */

import { complete, type Model, type UserMessage } from "@earendil-works/pi-ai";
import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";

// Tunables (seconds)
const MIN_TIMEOUT = 5;
const MAX_TIMEOUT = 600; // 10 min hard cap
const DEFAULT_TIMEOUT = 60; // fallback when LLM estimation fails
const FAST_PATH_TIMEOUT = 15; // for trivially fast commands
const ESTIMATOR_TIMEOUT_MS = 8000; // give up on the estimator after this

// Preferred estimator models, in priority order. The first one with configured
// auth wins. Override with env var PI_BASH_TIMEOUT_MODEL="provider/id".
// Patterns are matched against `${provider}/${id}` substring, case-insensitive.
const FAST_MODEL_PATTERNS = [
	"anthropic/claude-haiku",
	"anthropic/claude-3-5-haiku",
	"anthropic/claude-3-haiku",
	"openai/gpt-5-nano",
	"openai/gpt-5-mini",
	"openai/gpt-4.1-nano",
	"openai/gpt-4o-mini",
	"google/gemini-2.5-flash-lite",
	"google/gemini-2.5-flash",
	"google/gemini-2.0-flash",
	"google/gemini-flash",
	"groq/",
	"cerebras/",
	"deepseek/deepseek-chat",
	"haiku",
	"mini",
	"nano",
	"flash",
];

// Commands we consider trivially fast; skip the LLM call.
const FAST_COMMAND_RE =
	/^\s*(ls|pwd|whoami|date|echo|cat|head|tail|wc|which|type|env|printenv|true|false|hostname|uname|id|basename|dirname|realpath)\b/;
const FAST_GIT_RE = /^\s*git\s+(status|log|diff|branch|show|rev-parse|config)\b/;

const SYSTEM_PROMPT = `You estimate a safe upper-bound timeout (in seconds) for a shell command.
Rules:
- Output ONLY a single positive integer (seconds). No units, no explanation.
- Be generous but not absurd. Prefer the smallest plausible upper bound.
- Trivial commands (ls, cat, grep, git status, simple scripts): 10-30.
- Builds, installs, tests, large compiles: 120-600.
- Network ops (curl, wget, ssh, gh): 30-120.
- Anything that could legitimately run forever (servers, watchers, tail -f, sleep with large N): 30 (we expect the agent to background it instead).
- Hard maximum: ${MAX_TIMEOUT}.
- Hard minimum: ${MIN_TIMEOUT}.`;

function parseSeconds(text: string): number | null {
	const m = text.trim().match(/^-?\d+/);
	if (!m) return null;
	const n = Number.parseInt(m[0], 10);
	if (!Number.isFinite(n) || n <= 0) return null;
	return n;
}

function clamp(n: number): number {
	return Math.max(MIN_TIMEOUT, Math.min(MAX_TIMEOUT, Math.floor(n)));
}

function fastPathTimeout(command: string): number | null {
	if (FAST_COMMAND_RE.test(command) || FAST_GIT_RE.test(command)) {
		// Only treat as fast if there's no pipe/&&/; chain that could be slow.
		if (!/[|&;]|\$\(/.test(command)) return FAST_PATH_TIMEOUT;
	}
	return null;
}

function pickEstimatorModel(modelRegistry: any, fallback: Model<any> | undefined): Model<any> | undefined {
	const override = process.env.PI_BASH_TIMEOUT_MODEL;
	const available: Model<any>[] = modelRegistry.getAvailable?.() ?? [];

	if (override) {
		const [prov, ...rest] = override.split("/");
		const id = rest.join("/");
		const direct = modelRegistry.find?.(prov, id);
		if (direct) return direct;
		// Fallback: substring match in available list.
		const hit = available.find((m) => `${m.provider}/${m.id}`.toLowerCase().includes(override.toLowerCase()));
		if (hit) return hit;
	}

	for (const pattern of FAST_MODEL_PATTERNS) {
		const p = pattern.toLowerCase();
		const hit = available.find((m) => `${m.provider}/${m.id}`.toLowerCase().includes(p));
		if (hit) return hit;
	}

	// Last resort: cheapest available by input cost, then fall back to the agent's current model.
	if (available.length > 0) {
		const byCost = [...available].sort((a, b) => (a.cost?.input ?? Infinity) - (b.cost?.input ?? Infinity));
		return byCost[0] ?? fallback;
	}
	return fallback;
}

export default function (pi: ExtensionAPI) {
	const cache = new Map<string, number>();
	let announcedEstimator: string | undefined;

	async function estimateTimeout(
		command: string,
		ctx: { model: Model<any> | undefined; modelRegistry: any; signal?: AbortSignal; ui?: any },
	): Promise<number> {
		if (cache.has(command)) return cache.get(command)!;

		const fast = fastPathTimeout(command);
		if (fast !== null) {
			cache.set(command, fast);
			return fast;
		}

		const model = pickEstimatorModel(ctx.modelRegistry, ctx.model);
		if (!model) return DEFAULT_TIMEOUT;

		const tag = `${model.provider}/${model.id}`;
		if (announcedEstimator !== tag) {
			announcedEstimator = tag;
			ctx.ui?.setStatus?.("bash-timeout", `estimator: ${tag}`);
		}

		try {
			const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
			if (!auth.ok || !auth.apiKey) return DEFAULT_TIMEOUT;

			const userMessage: UserMessage = {
				role: "user",
				content: [{ type: "text", text: `Command:\n\n\`\`\`\n${command}\n\`\`\`\n\nTimeout in seconds:` }],
				timestamp: Date.now(),
			};

			// Race against ESTIMATOR_TIMEOUT_MS so a slow estimator never blocks the tool call.
			const ac = new AbortController();
			const timer = setTimeout(() => ac.abort(), ESTIMATOR_TIMEOUT_MS);
			const signal = ctx.signal
				? AbortSignal.any([ctx.signal, ac.signal])
				: ac.signal;

			let response;
			try {
				response = await complete(
					model,
					{ systemPrompt: SYSTEM_PROMPT, messages: [userMessage] },
					{ apiKey: auth.apiKey, headers: auth.headers, signal },
				);
			} finally {
				clearTimeout(timer);
			}

			if (response.stopReason === "aborted") return DEFAULT_TIMEOUT;

			const text = response.content
				.filter((c: any): c is { type: "text"; text: string } => c.type === "text")
				.map((c: any) => c.text)
				.join("")
				.trim();

			const n = parseSeconds(text);
			const result = n === null ? DEFAULT_TIMEOUT : clamp(n);
			cache.set(command, result);
			return result;
		} catch {
			return DEFAULT_TIMEOUT;
		}
	}

	pi.on("tool_call", async (event, ctx) => {
		if (!isToolCallEventType("bash", event)) return;

		const input = event.input as { command: string; timeout?: number };
		if (typeof input.command !== "string" || input.command.length === 0) return;

		// If the LLM already set a timeout, just clamp it to the hard cap.
		if (typeof input.timeout === "number" && input.timeout > 0) {
			const clamped = Math.min(input.timeout, MAX_TIMEOUT);
			if (clamped !== input.timeout) {
				input.timeout = clamped;
				ctx.ui.setStatus("bash-timeout", `clamped to ${clamped}s`);
			}
			return;
		}

		// Estimate.
		ctx.ui.setStatus("bash-timeout", "estimating timeout…");
		const seconds = await estimateTimeout(input.command, {
			model: ctx.model,
			modelRegistry: ctx.modelRegistry,
			signal: ctx.signal,
			ui: ctx.ui,
		});
		input.timeout = seconds;
		ctx.ui.setStatus("bash-timeout", `timeout=${seconds}s`);
	});

	pi.registerCommand("bash-timeout-cache", {
		description: "Show or clear the bash-timeout estimate cache",
		handler: async (args, ctx) => {
			const sub = (args ?? "").trim();
			if (sub === "clear") {
				cache.clear();
				announcedEstimator = undefined;
				ctx.ui.notify("bash-timeout cache cleared", "info");
				return;
			}
			const entries = [...cache.entries()].map(([cmd, t]) => `${t}s\t${cmd}`).join("\n");
			ctx.ui.notify(entries || "(empty)", "info");
		},
	});

	pi.registerCommand("bash-timeout-model", {
		description: "Show which model bash-timeout would use for estimation",
		handler: async (_args, ctx) => {
			const m = pickEstimatorModel(ctx.modelRegistry, ctx.model);
			if (!m) {
				ctx.ui.notify("No estimator model available", "warning");
				return;
			}
			const override = process.env.PI_BASH_TIMEOUT_MODEL;
			const src = override ? `env PI_BASH_TIMEOUT_MODEL=${override}` : "auto-picked";
			ctx.ui.notify(`Estimator: ${m.provider}/${m.id}  (${src})`, "info");
		},
	});
}
