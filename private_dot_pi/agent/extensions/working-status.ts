/**
 * working-status — replace pi's plain "Working..." loader with a live,
 * detailed status line while the agent is streaming.
 *
 * Instead of just "Working...", you get something like:
 *
 *   ⏱ 0:12 · sonnet-4 · turn 2 · ctx 45% (92k) · ⚙ bash, read · esc to stop
 *
 * Components (each shown only when known):
 *   - elapsed time since the current prompt started (mm:ss, or Ns under 60s)
 *   - active model id (provider prefix stripped)
 *   - current turn number (1-based)
 *   - context-window usage: percent + approximate token count
 *   - currently-running tools (deduped), or "thinking" while the model streams
 *     text before any tool call
 *   - an "esc to stop" hint (the custom message overrides pi's default which
 *     normally carries the interrupt hint)
 *
 * The line is refreshed on a timer so the elapsed clock ticks even when no
 * events are firing (e.g. waiting on a slow provider response).
 *
 * Commands:
 *   /working-status off     Restore pi's default "Working..." message
 *   /working-status on      Re-enable the detailed status line
 *   /working-status         Show current on/off state
 *
 * Install: lives in ~/.pi/agent/extensions/ (auto-discovered). /reload after edits.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const TICK_MS = 1000; // how often the elapsed clock refreshes
const INTERRUPT_HINT = "esc to stop";

export default function (pi: ExtensionAPI) {
	let enabled = true;

	// Per-turn state
	let startTime = 0;
	let turnDisplay = 0; // 1-based turn number, 0 = not started
	let streaming = false; // model has produced output this turn
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

	const fmtTokens = (n: number): string => {
		if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
		if (n >= 1000) return `${Math.round(n / 1000)}k`;
		return `${n}`;
	};

	// "anthropic/claude-sonnet-4" -> "claude-sonnet-4"; keep it short-ish.
	const shortModel = (id: string): string => {
		const tail = id.includes("/") ? id.slice(id.lastIndexOf("/") + 1) : id;
		return tail.replace(/^claude-/, "");
	};

	const buildMessage = (ctx: ExtensionContext): string => {
		const parts: string[] = [];

		parts.push(`⏱ ${fmtElapsed(Date.now() - startTime)}`);

		const model = ctx.model?.id;
		if (model) parts.push(shortModel(model));

		if (turnDisplay > 0) parts.push(`turn ${turnDisplay}`);

		const usage = ctx.getContextUsage?.();
		if (usage && usage.percent != null) {
			const tok = usage.tokens != null ? ` (${fmtTokens(usage.tokens)})` : "";
			parts.push(`ctx ${Math.round(usage.percent)}%${tok}`);
		}

		if (runningTools.size > 0) {
			const names = [...new Set(runningTools.values())];
			const shown = names.slice(0, 3).join(", ");
			const extra = names.length > 3 ? ` +${names.length - 3}` : "";
			parts.push(`⚙ ${shown}${extra}`);
		} else if (streaming) {
			parts.push("writing");
		} else {
			parts.push("thinking");
		}

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
		// Don't keep the process alive just for the cosmetic clock.
		ticker.unref?.();
	};

	const stopTicker = () => {
		if (ticker) {
			clearInterval(ticker);
			ticker = undefined;
		}
	};

	const resetTurnState = () => {
		startTime = Date.now();
		turnDisplay = 0;
		streaming = false;
		runningTools.clear();
	};

	pi.on("agent_start", async (_event, ctx) => {
		if (!enabled) return;
		resetTurnState();
		startTicker(ctx);
	});

	pi.on("turn_start", async (event, ctx) => {
		if (!enabled) return;
		// turnIndex is 0-based; show 1-based. A new turn means fresh tool set.
		turnDisplay = (event.turnIndex ?? turnDisplay) + 1;
		streaming = false;
		runningTools.clear();
		lastCtx = ctx;
		refresh();
	});

	pi.on("message_update", async (_event, ctx) => {
		if (!enabled) return;
		streaming = true;
		lastCtx = ctx;
		// No explicit refresh: the ticker handles cadence and avoids
		// thrashing setWorkingMessage on every streamed token.
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
		// Restore pi's default working message for the idle/next state.
		lastCtx?.ui.setWorkingMessage();
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
