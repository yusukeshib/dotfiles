/**
 * working-status — replace pi's plain "Working..." loader with a live,
 * detailed status line that tracks the agent through every phase of a turn.
 *
 * Examples (the activity segment changes as the turn progresses):
 *
 *   ⏱ 0:02 · turn 1 · requesting api.anthropic.com…      (HTTP request in flight)
 *   ⏱ 0:04 · turn 1 · receiving reasoning stream… 1.2 KB  (thinking stream)
 *   ⏱ 0:07 · turn 1 · receiving text stream… 4.8 KB       (assistant text)
 *   ⏱ 0:08 · turn 1 · receiving tool call… 320 B          (tool call args)
 *   ⏱ 0:09 · turn 2 · ⚙ running bash, read · esc to stop
 *
 * Fixed segments (shown when known): elapsed clock, turn number, and an
 * "esc to stop" hint. Model id and context-window usage are intentionally
 * omitted here because pi's footer already shows them.
 *
 * Activity segment (most specific wins):
 *   ⚙ running <tools>           one or more tools executing (deduped, max 3)
 *   requesting <host>…          HTTP request sent, awaiting response headers
 *   receiving reasoning stream… <n> streaming a reasoning block (+ decoded bytes)
 *   receiving text stream… <n>      streaming assistant text (+ decoded bytes)
 *   receiving tool call… <n>        streaming a tool call (+ decoded bytes)
 *   HTTP <status>               last response returned a non-2xx status
 *   connected, waiting…         response started, nothing classified yet
 *
 * Commands:
 *   /working-status off   Restore pi's default "Working..." message
 *   /working-status on    Re-enable the detailed status line
 *   /working-status       Show current on/off state
 *
 * Install: lives in ~/.pi/agent/extensions/ (auto-discovered). /reload after edits.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const TICK_MS = 1000; // how often the elapsed clock refreshes
const INTERRUPT_HINT = "esc to stop";

type StreamKind = "thinking" | "text" | "toolcall" | undefined;

export default function (pi: ExtensionAPI) {
	let enabled = true;

	// Per-turn / per-request state
	let startTime = 0;
	let turnDisplay = 0; // 1-based turn number, 0 = not started
	let requesting = false; // HTTP request sent, response headers not yet received
	let streamKind: StreamKind; // what the model is currently streaming
	let lastBadStatus = 0; // last non-2xx HTTP status, 0 = none
	let recvBytes = 0; // cumulative decoded stream bytes for the current response
	const runningTools = new Map<string, string>(); // toolCallId -> toolName
	let ticker: ReturnType<typeof setInterval> | undefined;
	let lastCtx: ExtensionContext | undefined;

	const fmtElapsed = (ms: number): string => {
		const total = Math.max(0, Math.floor(ms / 1000));
		if (total < 60) return `${total}s`;
		const m = Math.floor(total / 60);
		const s = total % 60;
		return `${m}:${String(s).padStart(2, "0")}`;
	};

	// Decoded content bytes received so far (not raw HTTP bytes: SSE framing and
	// any transport compression are not counted — this measures the assistant
	// text/reasoning/tool-call payload as it streams in).
	const fmtBytes = (n: number): string => {
		if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)} MB`;
		if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
		return `${n} B`;
	};

	// "https://api.anthropic.com/v1" -> "api.anthropic.com"; fall back to provider.
	const requestTarget = (ctx: ExtensionContext): string => {
		const model = ctx.model;
		if (model?.baseUrl) {
			try {
				return new URL(model.baseUrl).host;
			} catch {
				/* not a parseable URL, fall through */
			}
		}
		return model?.provider ?? "provider";
	};

	const activity = (ctx: ExtensionContext): string => {
		if (runningTools.size > 0) {
			const names = [...new Set(runningTools.values())];
			const shown = names.slice(0, 3).join(", ");
			const extra = names.length > 3 ? ` +${names.length - 3}` : "";
			return `⚙ running ${shown}${extra}`;
		}
		if (requesting) return `requesting ${requestTarget(ctx)}…`;
		if (lastBadStatus) return `HTTP ${lastBadStatus}`;
		const got = recvBytes > 0 ? ` ${fmtBytes(recvBytes)}` : "";
		switch (streamKind) {
			case "thinking":
				return `receiving reasoning stream…${got}`;
			case "text":
				return `receiving text stream…${got}`;
			case "toolcall":
				return `receiving tool call…${got}`;
			default:
				return "connected, waiting…";
		}
	};

	const buildMessage = (ctx: ExtensionContext): string => {
		const parts: string[] = [];
		parts.push(`⏱ ${fmtElapsed(Date.now() - startTime)}`);

		if (turnDisplay > 0) parts.push(`turn ${turnDisplay}`);

		parts.push(activity(ctx));
		parts.push(INTERRUPT_HINT);
		return parts.join(" · ");
	};

	const refresh = () => {
		if (!enabled || !lastCtx) return;
		lastCtx.ui.setWorkingMessage(buildMessage(lastCtx));
	};

	const startTicker = (ctx: ExtensionContext) => {
		lastCtx = ctx;
		refresh();
		if (ticker) clearInterval(ticker);
		ticker = setInterval(refresh, TICK_MS);
		ticker.unref?.(); // don't keep the process alive for a cosmetic clock
	};

	const stopTicker = () => {
		if (ticker) {
			clearInterval(ticker);
			ticker = undefined;
		}
	};

	pi.on("agent_start", async (_event, ctx) => {
		if (!enabled) return;
		startTime = Date.now();
		turnDisplay = 0;
		requesting = false;
		streamKind = undefined;
		lastBadStatus = 0;
		runningTools.clear();
		startTicker(ctx);
	});

	pi.on("turn_start", async (event, ctx) => {
		if (!enabled) return;
		turnDisplay = (event.turnIndex ?? turnDisplay) + 1; // turnIndex is 0-based
		streamKind = undefined;
		lastBadStatus = 0;
		runningTools.clear();
		lastCtx = ctx;
		refresh();
	});

	pi.on("before_provider_request", async (_event, ctx) => {
		if (!enabled) return;
		requesting = true;
		streamKind = undefined;
		lastBadStatus = 0;
		recvBytes = 0; // fresh response, fresh byte count
		lastCtx = ctx;
		refresh();
	});

	pi.on("after_provider_response", async (event, ctx) => {
		if (!enabled) return;
		requesting = false;
		if (event.status >= 400) lastBadStatus = event.status;
		lastCtx = ctx;
		refresh();
	});

	pi.on("message_update", async (event, ctx) => {
		if (!enabled) return;
		requesting = false;
		lastBadStatus = 0; // real content is arriving; supersede any stale bad status
		const ev = event.assistantMessageEvent as { type?: string; delta?: unknown } | undefined;
		const t = ev?.type ?? "";
		if (t.startsWith("thinking")) streamKind = "thinking";
		else if (t.startsWith("text")) streamKind = "text";
		else if (t.startsWith("toolcall")) streamKind = "toolcall";
		if (typeof ev?.delta === "string") {
			recvBytes += Buffer.byteLength(ev.delta, "utf8");
		}
		lastCtx = ctx;
		// No explicit refresh on every token: the ticker handles cadence and
		// avoids thrashing setWorkingMessage. The phase label is sticky until
		// the next classified event, so 1s latency on transitions is fine.
	});

	pi.on("tool_execution_start", async (event, ctx) => {
		if (!enabled) return;
		runningTools.set(event.toolCallId, event.toolName);
		lastCtx = ctx;
		refresh();
	});

	pi.on("tool_execution_end", async (event, ctx) => {
		if (!enabled) return;
		runningTools.delete(event.toolCallId);
		lastCtx = ctx;
		refresh();
	});

	pi.on("agent_end", async (_event, _ctx) => {
		stopTicker();
		runningTools.clear();
		lastCtx?.ui.setWorkingMessage(); // restore default for idle/next state
		lastCtx = undefined;
	});

	pi.on("session_shutdown", async (_event, _ctx) => {
		stopTicker();
		runningTools.clear();
	});

	pi.registerCommand("working-status", {
		description: "Toggle the detailed Working status line (on/off).",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (!arg) {
				ctx.ui.notify(`Working status: ${enabled ? "on" : "off"}`, "info");
				return;
			}
			if (arg !== "on" && arg !== "off") {
				ctx.ui.notify("Usage: /working-status [on|off]", "error");
				return;
			}
			enabled = arg === "on";
			if (!enabled) {
				stopTicker();
				ctx.ui.setWorkingMessage(); // back to default
			}
			ctx.ui.notify(`Working status ${enabled ? "enabled" : "disabled"}`, "info");
		},
	});
}
