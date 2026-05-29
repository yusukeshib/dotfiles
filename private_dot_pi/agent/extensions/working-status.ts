/**
 * working-status — replace pi's plain "Working..." loader with a live,
 * detailed status line that tracks the agent through every phase of a turn.
 *
 * Examples (the activity segment changes as the turn progresses):
 *
 *   ⏱ 0:02 · turn 1 · requesting api.anthropic.com…                 (request in flight)
 *   ⏱ 0:04 · turn 1 · receiving reasoning stream… 240 tok · 1.2 KB   (thinking stream)
 *   ⏱ 0:07 · turn 1 · receiving text stream… 1.1k tok · 180 tok/s · 4.8 KB
 *   ⏱ 0:08 · turn 1 · ⚙ bash: npm test -- --watch=false             (single tool: args)
 *   ⏱ 0:09 · turn 2 · ⚙ running bash, read · esc to stop            (multiple tools)
 *
 * Fixed segments (shown when known): elapsed clock, turn number, and an
 * "esc to stop" hint. Model id and context-window usage are intentionally
 * omitted here because pi's footer already shows them.
 *
 * Activity segment (most specific wins):
 *   ⚙ <tool>: <args>            single tool executing (bash command / file path / pattern)
 *   ⚙ running <tools>           multiple tools executing (deduped names, max 3)
 *   sending request to <host>…  request being sent (first ~0.4s)
 *   waiting for response… <n>s  request sent, awaiting any response (with wait clock)
 *   receiving reasoning stream… provider streaming a reasoning block (+ tok / tok·s / bytes)
 *   receiving text stream…      provider streaming assistant text (+ tok / tok·s / bytes)
 *   receiving tool call…        provider streaming a tool call (+ tok / tok·s / bytes)
 *   HTTP <status>               last response returned a non-2xx status
 *   connected, waiting… (ttft)  headers received, awaiting first token
 *
 * Token counts come from the provider's streamed usage (Anthropic, Bedrock,
 * Mistral, Google update output tokens mid-stream); tok/s and ttft are derived
 * locally. Byte counts are decoded payload size (not raw HTTP bytes).
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
// There is no "request fully sent" event, so treat the first moment after
// before_provider_request as "sending", then switch to "waiting for response".
const SEND_GRACE_MS = 400;

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
	let outTokens = 0; // output tokens reported so far this response (major providers)
	let reqStartAt = 0; // when the current provider request was sent
	let firstTokenAt = 0; // when the first stream token arrived (for TTFT + tok/s)
	const runningTools = new Map<string, { name: string; detail: string }>();
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

	const fmtCount = (n: number): string => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

	// Extract a short, single-line summary of what a tool call is doing from its
	// arguments. Field names match pi's built-in tool schemas.
	const toolDetail = (name: string, args: unknown): string => {
		const a = (args ?? {}) as Record<string, unknown>;
		let raw: unknown;
		if (name === "bash") raw = a.command;
		else if (name === "grep" || name === "find") raw = a.pattern;
		else raw = a.path; // read, write, edit, ls
		if (typeof raw !== "string" || !raw) return "";
		const oneLine = raw.replace(/\s+/g, " ").trim();
		return oneLine.length > 40 ? `${oneLine.slice(0, 39)}…` : oneLine;
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
			const entries = [...runningTools.values()];
			// Single tool: show its argument detail (command/path/pattern).
			if (entries.length === 1) {
				const { name, detail } = entries[0]!;
				return detail ? `⚙ ${name}: ${detail}` : `⚙ running ${name}`;
			}
			const names = [...new Set(entries.map((e) => e.name))];
			const shown = names.slice(0, 3).join(", ");
			const extra = names.length > 3 ? ` +${names.length - 3}` : "";
			return `⚙ running ${shown}${extra}`;
		}
		if (requesting) {
			const host = requestTarget(ctx);
			const waited = reqStartAt ? Date.now() - reqStartAt : 0;
			if (waited < SEND_GRACE_MS) return `sending request to ${host}…`;
			return `waiting for response from ${host}… ${Math.round(waited / 1000)}s`;
		}
		if (lastBadStatus) return `HTTP ${lastBadStatus}`;

		// Stream progress: tokens (if reported), tok/s, then decoded bytes.
		const bits: string[] = [];
		if (outTokens > 0) bits.push(`${fmtCount(outTokens)} tok`);
		if (outTokens > 0 && firstTokenAt > 0) {
			const secs = (Date.now() - firstTokenAt) / 1000;
			if (secs >= 0.5) bits.push(`${Math.round(outTokens / secs)} tok/s`);
		}
		if (recvBytes > 0) bits.push(fmtBytes(recvBytes));
		const got = bits.length ? ` ${bits.join(" · ")}` : "";
		switch (streamKind) {
			case "thinking":
				return `receiving reasoning stream…${got}`;
			case "text":
				return `receiving text stream…${got}`;
			case "toolcall":
				return `receiving tool call…${got}`;
			default: {
				const ttft = firstTokenAt && reqStartAt ? ` (ttft ${((firstTokenAt - reqStartAt) / 1000).toFixed(1)}s)` : "";
				return `connected, waiting…${ttft}`;
			}
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

	const resetResponse = () => {
		streamKind = undefined;
		lastBadStatus = 0;
		recvBytes = 0;
		outTokens = 0;
		firstTokenAt = 0;
		reqStartAt = 0;
	};

	pi.on("agent_start", async (_event, ctx) => {
		if (!enabled) return;
		startTime = Date.now();
		turnDisplay = 0;
		requesting = false;
		resetResponse();
		runningTools.clear();
		startTicker(ctx);
	});

	pi.on("turn_start", async (event, ctx) => {
		if (!enabled) return;
		turnDisplay = (event.turnIndex ?? turnDisplay) + 1; // turnIndex is 0-based
		resetResponse();
		runningTools.clear();
		lastCtx = ctx;
		refresh();
	});

	pi.on("before_provider_request", async (_event, ctx) => {
		if (!enabled) return;
		requesting = true;
		resetResponse(); // fresh response: clear bytes/tokens/ttft
		reqStartAt = Date.now();
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
		if (firstTokenAt === 0) firstTokenAt = Date.now();
		const ev = event.assistantMessageEvent as { type?: string; delta?: unknown } | undefined;
		const t = ev?.type ?? "";
		if (t.startsWith("thinking")) streamKind = "thinking";
		else if (t.startsWith("text")) streamKind = "text";
		else if (t.startsWith("toolcall")) streamKind = "toolcall";
		if (typeof ev?.delta === "string") {
			recvBytes += Buffer.byteLength(ev.delta, "utf8");
		}
		// Live output-token count (Anthropic/Bedrock/Mistral/Google update this mid-stream).
		const usage = (event.message as { usage?: { output?: number } } | undefined)?.usage;
		if (typeof usage?.output === "number" && usage.output > outTokens) {
			outTokens = usage.output;
		}
		lastCtx = ctx;
		// No explicit refresh on every token: the ticker handles cadence and
		// avoids thrashing setWorkingMessage. The phase label is sticky until
		// the next classified event, so 1s latency on transitions is fine.
	});

	pi.on("tool_execution_start", async (event, ctx) => {
		if (!enabled) return;
		runningTools.set(event.toolCallId, {
			name: event.toolName,
			detail: toolDetail(event.toolName, event.args),
		});
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
