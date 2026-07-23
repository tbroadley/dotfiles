/**
 * auto-mode — "auto" model selection for pi, in the spirit of Claude Code's
 * auto mode.
 *
 * When enabled, pi stops caring about the exact model you picked and instead
 * derives the model to run from the *family* of the currently selected model:
 *
 *   - Anthropic-family model  ->  claude-sonnet-5
 *   - OpenAI-family model     ->  gpt-5.6-luna
 *   - anything else           ->  hard error that stops the agent
 *
 * Family is detected from the resolved model's `api` (e.g. "anthropic-messages"
 * vs "openai-responses"/"openai-completions"), which works even for proxy
 * providers such as `hawk` that serve both Anthropic and OpenAI backends under
 * a single provider id. A couple of id/name heuristics act as a fallback for
 * providers that leave `api` non-standard.
 *
 * The target model is looked up in the model registry (preferring the current
 * model's provider, then any available/known provider). If the target model is
 * not available, or the current model is neither Anthropic nor OpenAI, auto
 * mode throws. Thrown from `before_agent_start`, that error stops the agent
 * before it runs — which is the intended behaviour.
 *
 * Auto mode is a toggle (off by default so it never silently hijacks a normal
 * session):
 *   - `--auto-mode` CLI flag starts a session with it enabled.
 *   - `/auto-mode [on|off|status]` toggles/queries it at runtime.
 *
 * While enabled it also re-derives the model whenever you change models via
 * `/model` or Ctrl+P, so the selection stays "auto".
 */
import type { Model } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Family = "anthropic" | "openai" | "other";

const TARGET_MODEL_ID: Record<Exclude<Family, "other">, string> = {
	anthropic: "claude-sonnet-5",
	openai: "gpt-5.6-luna",
};

const STATUS_KEY = "auto-mode";

/** Detect the model family from its resolved API, with id/name/provider fallbacks. */
function detectFamily(model: Model<any>): Family {
	const api = String(model.api ?? "").toLowerCase();
	if (api.startsWith("anthropic")) return "anthropic";
	if (api.startsWith("openai")) return "openai";

	// Fallback for providers that don't set a standard `api` string.
	const hint = `${model.provider ?? ""} ${model.id ?? ""} ${model.name ?? ""}`.toLowerCase();
	if (/claude|anthropic/.test(hint)) return "anthropic";
	if (/\bgpt|openai|\bo[0-9]/.test(hint)) return "openai";

	return "other";
}

/**
 * Find the target model in the registry. Prefer the current model's provider so
 * that e.g. a hawk session stays on hawk, then fall back to any provider that
 * exposes a model with the target id.
 */
function resolveTarget(ctx: ExtensionContext, currentProvider: string, targetId: string): Model<any> | undefined {
	const preferred = ctx.modelRegistry.find(currentProvider, targetId);
	if (preferred) return preferred;

	for (const model of ctx.modelRegistry.getAvailable()) {
		if (model.id === targetId) return model;
	}
	for (const model of ctx.modelRegistry.getAll()) {
		if (model.id === targetId) return model;
	}
	return undefined;
}

export default function autoMode(pi: ExtensionAPI): void {
	let enabled = false;
	let isEnforcing = false;

	pi.registerFlag("auto-mode", {
		description: "Start with auto model mode enabled (derive the model from the agent's family)",
		type: "boolean",
		default: false,
	});

	function refreshStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		if (enabled) {
			const current = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "unknown";
			ctx.ui.setStatus(STATUS_KEY, `auto: ${current}`);
		} else {
			ctx.ui.setStatus(STATUS_KEY, "");
		}
	}

	/**
	 * Enforce the auto-mode mapping for the current model. Returns a human
	 * readable description of what changed, or undefined if nothing changed.
	 * Throws when the family is unsupported or the target model is unavailable —
	 * callers in `before_agent_start` let that error stop the agent.
	 */
	async function applyAutoMode(ctx: ExtensionContext): Promise<string | undefined> {
		const model = ctx.model;
		if (!model) {
			throw new Error("Auto mode is enabled but there is no active model to derive a selection from.");
		}

		const family = detectFamily(model);
		if (family === "other") {
			throw new Error(
				`Auto mode only supports Anthropic and OpenAI models, but the current model ` +
					`"${model.provider}/${model.id}" (api "${model.api}") is neither. ` +
					`Switch to an Anthropic or OpenAI model, or disable auto mode with /auto-mode off.`,
			);
		}

		const targetId = TARGET_MODEL_ID[family];
		if (model.id === targetId) return undefined; // Already on the right model.

		const target = resolveTarget(ctx, model.provider, targetId);
		if (!target) {
			throw new Error(
				`Auto mode wants the ${family} model "${targetId}" but it is not available in any ` +
					`configured provider. Make sure "${targetId}" is enabled/reachable, or disable auto ` +
					`mode with /auto-mode off.`,
			);
		}

		isEnforcing = true;
		try {
			const changed = await pi.setModel(target);
			if (!changed) {
				throw new Error(
					`Auto mode could not switch to "${target.provider}/${target.id}" — no API key is ` +
						`available for it. Run /login for that provider, or disable auto mode with /auto-mode off.`,
				);
			}
		} finally {
			isEnforcing = false;
		}

		return `Auto mode selected ${target.provider}/${target.id} (${family}).`;
	}

	pi.on("session_start", async (_event, ctx) => {
		enabled = Boolean(pi.getFlag("auto-mode"));
		if (!enabled) {
			refreshStatus(ctx);
			return;
		}
		// Don't crash startup: surface any problem as a notification. The agent
		// itself is still gated by before_agent_start below.
		try {
			const msg = await applyAutoMode(ctx);
			if (msg) ctx.ui.notify(msg, "info");
		} catch (error) {
			ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
		refreshStatus(ctx);
	});

	// The enforcement point that can stop the agent: a thrown error here aborts
	// the run before the LLM is called.
	pi.on("before_agent_start", async (_event, ctx) => {
		if (!enabled) return;
		await applyAutoMode(ctx);
		refreshStatus(ctx);
	});

	// Keep the selection "auto" when the user changes models manually.
	pi.on("model_select", async (event, ctx) => {
		if (!enabled || isEnforcing) return;
		try {
			const msg = await applyAutoMode(ctx);
			if (msg) ctx.ui.notify(`${msg} (auto mode is on)`, "warning");
		} catch (error) {
			ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
		refreshStatus(ctx);
	});

	pi.registerCommand("auto-mode", {
		description: "Toggle auto model mode (Anthropic -> claude-sonnet-5, OpenAI -> gpt-5.6-luna)",
		getArgumentCompletions: (prefix: string) => {
			const items = ["on", "off", "status"].map((value) => ({ value, label: value }));
			const filtered = items.filter((item) => item.value.startsWith(prefix.trim()));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			const want = arg === "on" ? true : arg === "off" ? false : arg === "status" ? enabled : !enabled;

			if (arg === "status") {
				const current = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "unknown";
				ctx.ui.notify(`Auto mode is ${enabled ? "on" : "off"} (model: ${current}).`, "info");
				return;
			}

			if (want === enabled) {
				ctx.ui.notify(`Auto mode is already ${enabled ? "on" : "off"}.`, "info");
				return;
			}

			enabled = want;
			if (!enabled) {
				ctx.ui.notify("Auto mode disabled.", "info");
				refreshStatus(ctx);
				return;
			}

			try {
				const msg = await applyAutoMode(ctx);
				ctx.ui.notify(msg ?? "Auto mode enabled (model already correct).", "info");
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
			}
			refreshStatus(ctx);
		},
	});
}
