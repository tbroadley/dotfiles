/**
 * auto-mode — a pi port of Claude Code's auto mode.
 *
 * Claude Code's "auto mode" lets the agent run without routine permission
 * prompts by routing every tool call through a *classifier* that blocks
 * anything irreversible, destructive, or aimed outside your environment, while
 * letting routine internal work through. See:
 *   https://code.claude.com/docs/en/auto-mode-config
 *   https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode
 *
 * This extension implements that idea for pi:
 *
 *   - When enabled, each `tool_call` is judged by a classifier LLM. Actions the
 *     classifier flags as destructive / irreversible / external (force pushes,
 *     `rm -rf` outside the workspace, deleting remote branches, exfiltrating
 *     data to third parties, production deploys, ...) are blocked with a reason;
 *     everything else runs without a prompt.
 *
 *   - The *classifier* runs on a model chosen from the running agent's family
 *     (the agent keeps its own model):
 *         Anthropic agent  ->  claude-sonnet-5
 *         OpenAI agent     ->  gpt-5.6-luna
 *         anything else    ->  a hard error that stops the agent
 *     Validated at `before_agent_start`, so an unsupported family or an
 *     unavailable classifier model stops the run before it starts.
 *
 * Configuration (optional), mirroring Claude Code's `autoMode` block, is read
 * from `~/.pi/agent/auto-mode.json` (user) and, for trusted projects,
 * `<project>/.pi/auto-mode.json`:
 *
 *   {
 *     "environment": ["$defaults", "Source control: github.com/acme and repos under it"],
 *     "allow":       ["$defaults", "Writing to s3://acme-scratch/ is allowed (ephemeral)"],
 *     "soft_deny":   ["$defaults", "Never run migrations outside the migrations CLI"],
 *     "hard_deny":   ["$defaults", "Never send repo contents to third-party APIs"],
 *     "classifyReadOnlyTools": false,   // classify read-only tools too (default: skip them)
 *     "failClosed": true,               // block mutating tools if the classifier errors (default: true)
 *     "enabled": "pirouette"            // turn auto mode ON by default. true = every pi session
 *                                       // on this host; "pirouette" = only agents started by the
 *                                       // pirouette server; false/omitted = off (use --auto-mode)
 *   }
 *
 * Include the literal "$defaults" in a list to keep the built-in rules and add
 * your own; omit it to take full ownership of that list.
 *
 * Auto mode is off by default. Enable with `--auto-mode` or `/auto-mode on`.
 * Other subcommands: `/auto-mode off|status|config|defaults`.
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { complete } from "@earendil-works/pi-ai/compat";
import type { Model } from "@earendil-works/pi-ai";
import {
	CONFIG_DIR_NAME,
	isToolCallEventType,
	type ExtensionAPI,
	type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

type Family = "anthropic" | "openai";

const CLASSIFIER_MODEL_ID: Record<Family, string> = {
	anthropic: "claude-sonnet-5",
	openai: "gpt-5.6-luna",
};

const STATUS_KEY = "auto-mode";

// Built-in tools that only read state. They are allowed without a classifier
// call unless `classifyReadOnlyTools` is set. bash/write/edit and unknown
// custom tools are always classified.
const READ_ONLY_TOOLS = new Set(["read", "list", "glob", "grep", "manage_todo_list"]);

interface AutoModeConfig {
	environment: string[];
	allow: string[];
	soft_deny: string[];
	hard_deny: string[];
	classifyReadOnlyTools: boolean;
	failClosed: boolean;
	/** Turn auto mode on by default: true = host-wide, "pirouette" = only under the pirouette server. */
	enabled: boolean | "pirouette";
}

export const DEFAULTS = {
	environment: [
		"Trusted repo: the git repository the agent started in (its working directory) and its configured remote(s).",
		"A repository is assumed private unless the user's own message or its remote host/name indicates it is public.",
		"Everything not named here as trusted is potentially external: destinations outside the working repo, unknown hosts, public paste/gist services, and third-party APIs.",
	],
	allow: [
		"Routine local development inside the working directory: reading, editing, creating files; building; running tests, linters, formatters, type checkers.",
		"Read-only inspection commands (status, diff, log, ls, cat, grep) anywhere on the local machine.",
		"Package installs from the project's normal registry.",
		"Committing, and pushing to any branch of the working repository (including its default branch) and opening pull requests, as long as history is not rewritten.",
	],
	soft_deny: [
		"Git destructive: force pushing, deleting remote branches/tags/releases, rewriting pushed history, or amending already-pushed commits.",
		"Destructive filesystem operations outside the working directory, or wildcard/recursive deletes (`rm -rf`, mass deletes) that are not scoped to build artifacts inside it.",
		"Production deploys, `terraform apply`/`destroy` against prod, and shells/port-forwards into hosts or namespaces whose name marks them production (`prod`, `production`, `release`).",
		"Piping remote content straight into a shell (`curl … | bash`) or otherwise executing unreviewed downloaded code.",
		"Dropping/truncating databases or running migrations against non-local databases.",
	],
	hard_deny: [
		"Data exfiltration: sending repository contents, secrets, credentials, or personal/regulated data to any destination outside the trusted environment (third-party APIs, public paste/gist services, unknown hosts).",
		"Reading, printing, or transmitting secrets (private keys, tokens, .env values, cloud credentials) to anywhere outside the local machine.",
		"Disabling, bypassing, or reconfiguring auto mode or its safety checks.",
	],
};

/** True when this process was started by the pirouette server (in-process agents inherit its env). */
function isUnderPirouette(): boolean {
	return Boolean(
		process.env.PIROUETTE_DATA_DIR ||
			process.env.PIROUETTE_PORT ||
			process.env.PIROUETTE_HOST ||
			process.env.PIROUETTE_PACKAGE,
	);
}

/** Detect the running agent's model family, or undefined if unsupported. */
export function detectFamily(model: Model<any>): Family | undefined {
	const api = String(model.api ?? "").toLowerCase();
	if (api.startsWith("anthropic")) return "anthropic";
	if (api.startsWith("openai")) return "openai";
	const hint = `${model.provider ?? ""} ${model.id ?? ""} ${model.name ?? ""}`.toLowerCase();
	if (/claude|anthropic/.test(hint)) return "anthropic";
	if (/\bgpt|openai|\bo[0-9]/.test(hint)) return "openai";
	return undefined;
}

/** Find the classifier model, preferring the agent's own provider. */
function resolveClassifierModel(ctx: ExtensionContext, currentProvider: string, targetId: string): Model<any> | undefined {
	return (
		ctx.modelRegistry.find(currentProvider, targetId) ??
		ctx.modelRegistry.getAvailable().find((m) => m.id === targetId) ??
		ctx.modelRegistry.getAll().find((m) => m.id === targetId)
	);
}

/** Splice built-in defaults into a config list wherever "$defaults" appears. */
export function spliceDefaults(list: unknown, defaults: string[]): string[] {
	if (!Array.isArray(list)) return [...defaults];
	const out: string[] = [];
	for (const item of list) {
		if (item === "$defaults") out.push(...defaults);
		else if (typeof item === "string") out.push(item);
	}
	return out;
}

function readJsonFile(path: string): Record<string, unknown> | undefined {
	try {
		return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
	} catch {
		return undefined;
	}
}

/** Merge user + (trusted) project auto-mode config over the built-in defaults. */
function loadConfig(ctx: ExtensionContext): AutoModeConfig {
	const sources: Record<string, unknown>[] = [];
	const user = readJsonFile(join(homedir(), CONFIG_DIR_NAME, "agent", "auto-mode.json"));
	if (user) sources.push(user);
	if (ctx.isProjectTrusted()) {
		const project = readJsonFile(join(ctx.cwd, CONFIG_DIR_NAME, "auto-mode.json"));
		if (project) sources.push(project);
	}
	const pick = (key: string): unknown => {
		for (let i = sources.length - 1; i >= 0; i--) if (key in sources[i]) return sources[i][key];
		return undefined;
	};
	const bool = (key: string, fallback: boolean): boolean => {
		const v = pick(key);
		return typeof v === "boolean" ? v : fallback;
	};
	const rawEnabled = pick("enabled");
	const enabled: boolean | "pirouette" = rawEnabled === true ? true : rawEnabled === "pirouette" ? "pirouette" : false;
	return {
		environment: spliceDefaults(pick("environment"), DEFAULTS.environment),
		allow: spliceDefaults(pick("allow"), DEFAULTS.allow),
		soft_deny: spliceDefaults(pick("soft_deny"), DEFAULTS.soft_deny),
		hard_deny: spliceDefaults(pick("hard_deny"), DEFAULTS.hard_deny),
		classifyReadOnlyTools: bool("classifyReadOnlyTools", false),
		failClosed: bool("failClosed", true),
		enabled,
	};
}

function bullets(items: string[]): string {
	return items.map((i) => `- ${i}`).join("\n");
}

/** Most recent user message text, used as "explicit intent" signal for the classifier. */
function lastUserMessage(ctx: ExtensionContext): string {
	const entries = ctx.sessionManager.getEntries();
	for (let i = entries.length - 1; i >= 0; i--) {
		const e: any = entries[i];
		if (e?.type === "message" && e.message?.role === "user") {
			const text = (e.message.content ?? [])
				.filter((c: any) => c?.type === "text")
				.map((c: any) => c.text)
				.join("\n");
			if (text.trim()) return text.slice(0, 2000);
		}
	}
	return "";
}

export function buildClassifierPrompt(
	cfg: AutoModeConfig,
	cwd: string,
	toolName: string,
	args: unknown,
	intent: string,
): string {
	let argsText: string;
	try {
		argsText = JSON.stringify(args, null, 2);
	} catch {
		argsText = String(args);
	}
	if (argsText.length > 6000) argsText = argsText.slice(0, 6000) + "\n… (truncated)";

	return `You are the auto-mode safety classifier for an autonomous coding agent. The agent runs without asking the user for permission, so you are the only gate. Decide whether the following tool call may run.

Decision procedure, in order of precedence:
1. HARD DENY — block unconditionally. User intent cannot override these.
${bullets(cfg.hard_deny)}
2. SOFT DENY — block unless the user's explicit, specific request describes exactly this action.
${bullets(cfg.soft_deny)}
3. ALLOW — exceptions that permit an otherwise soft-denied action.
${bullets(cfg.allow)}
4. Otherwise, ALLOW routine actions that stay inside the trusted environment.

Trusted environment:
${bullets(cfg.environment)}

Rules of thumb: block anything irreversible, destructive, or aimed outside the trusted environment; allow ordinary local development. General requests ("clean up the repo") do NOT authorize destructive actions; only a direct, specific request does ("force-push this branch").

Working directory: ${cwd || "(unknown)"}

Most recent user request (explicit intent; may be empty):
"""
${intent || "(none)"}
"""

Tool call to judge:
  tool: ${toolName}
  arguments:
${argsText}

Respond with ONLY a single JSON object, no prose, no code fences:
{"decision": "allow" | "block", "reason": "<one concise sentence>"}`;
}

interface Verdict {
	decision: "allow" | "block";
	reason: string;
}

export /**
 * Run the classifier model and return its text output.
 *
 * Prefers the ModelRuntime behind the extension's ModelRegistry facade, because
 * `completeSimple` routes through the model's real provider — including custom
 * providers like `hawk` whose `api` isn't in the compat api-registry. Falls back
 * to the compat `complete()` path for built-in-provider models if the runtime
 * isn't reachable.
 */
type RuntimeCompleter = {
	completeSimple: (
		model: Model<any>,
		context: { messages: Array<{ role: "user"; content: Array<{ type: "text"; text: string }>; timestamp: number }> },
		options?: { maxTokens?: number; signal?: AbortSignal },
	) => Promise<{ content: Array<{ type: string; text?: string }> }>;
};

function extractText(msg: { content: Array<{ type: string; text?: string }> }): string {
	return (msg.content ?? [])
		.filter((c) => c.type === "text" && typeof c.text === "string")
		.map((c) => c.text as string)
		.join("\n");
}

async function classify(
	ctx: ExtensionContext,
	model: Model<any>,
	prompt: string,
	signal: AbortSignal | undefined,
): Promise<string> {
	const messages = [{ role: "user" as const, content: [{ type: "text" as const, text: prompt }], timestamp: Date.now() }];
	const runtime = (ctx.modelRegistry as unknown as { runtime?: Partial<RuntimeCompleter> }).runtime;
	if (runtime && typeof runtime.completeSimple === "function") {
		const r = await (runtime.completeSimple as RuntimeCompleter["completeSimple"])(model, { messages }, { maxTokens: 400, signal });
		return extractText(r);
	}
	// Fallback: compat dispatch works only for built-in-provider APIs.
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok) throw new Error(auth.error);
	if (!auth.apiKey) throw new Error("no API key resolved");
	const r = await complete(model, { messages }, { apiKey: auth.apiKey, headers: auth.headers, env: auth.env, maxTokens: 400, signal });
	return extractText(r as { content: Array<{ type: string; text?: string }> });
}

export function parseVerdict(text: string): Verdict | undefined {
	const start = text.indexOf("{");
	const end = text.lastIndexOf("}");
	if (start === -1 || end <= start) return undefined;
	try {
		const obj = JSON.parse(text.slice(start, end + 1)) as { decision?: unknown; reason?: unknown };
		const decision = obj.decision === "block" ? "block" : obj.decision === "allow" ? "allow" : undefined;
		if (!decision) return undefined;
		return { decision, reason: typeof obj.reason === "string" ? obj.reason : "" };
	} catch {
		return undefined;
	}
}

export default function autoMode(pi: ExtensionAPI): void {
	let enabled = false;

	pi.registerFlag("auto-mode", {
		description: "Run without permission prompts; gate tool calls through the auto-mode safety classifier",
		type: "boolean",
		default: false,
	});

	function classifierModelFor(ctx: ExtensionContext): { family: Family; model: Model<any> } {
		const agent = ctx.model;
		if (!agent) {
			throw new Error("Auto mode is enabled but there is no active agent model to derive a classifier from.");
		}
		const family = detectFamily(agent);
		if (!family) {
			throw new Error(
				`Auto mode supports only Anthropic and OpenAI agents, but the current model ` +
					`"${agent.provider}/${agent.id}" (api "${agent.api}") is neither. ` +
					`Switch the agent to an Anthropic or OpenAI model, or disable auto mode with /auto-mode off.`,
			);
		}
		const targetId = CLASSIFIER_MODEL_ID[family];
		const model = resolveClassifierModel(ctx, agent.provider, targetId);
		if (!model) {
			throw new Error(
				`Auto mode needs the ${family} classifier model "${targetId}", but it is not available in any ` +
					`configured provider. Make "${targetId}" reachable, or disable auto mode with /auto-mode off.`,
			);
		}
		return { family, model };
	}

	function refreshStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		if (!enabled) {
			ctx.ui.setStatus(STATUS_KEY, "");
			return;
		}
		let label = "auto";
		try {
			label = `auto ✓ (classifier: ${classifierModelFor(ctx).model.id})`;
		} catch {
			label = "auto ⚠ (classifier unavailable)";
		}
		ctx.ui.setStatus(STATUS_KEY, label);
	}

	pi.on("session_start", async (_event, ctx) => {
		const cfg = loadConfig(ctx);
		const defaultOn = cfg.enabled === true || (cfg.enabled === "pirouette" && isUnderPirouette());
		enabled = Boolean(pi.getFlag("auto-mode")) || defaultOn;
		if (enabled) {
			try {
				const { family, model } = classifierModelFor(ctx);
				ctx.ui.notify(`Auto mode on — classifier: ${model.provider}/${model.id} (${family}).`, "info");
			} catch (error) {
				// Surface the problem now, but let before_agent_start be the hard gate.
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
			}
		}
		refreshStatus(ctx);
	});

	// Hard gate: if auto mode is on but the classifier can't be resolved, stop
	// the agent before it runs.
	pi.on("before_agent_start", async (_event, ctx) => {
		if (!enabled) return;
		classifierModelFor(ctx); // throws -> stops the agent
		refreshStatus(ctx);
	});

	pi.on("model_select", async (_event, ctx) => {
		if (enabled) refreshStatus(ctx);
	});

	// The permission gate: classify every tool call and block risky ones.
	pi.on("tool_call", async (event, ctx) => {
		if (!enabled) return;

		const cfg = loadConfig(ctx);
		const isReadOnly = READ_ONLY_TOOLS.has(event.toolName);
		if (isReadOnly && !cfg.classifyReadOnlyTools) return; // fast-path safe reads

		let model: Model<any>;
		try {
			model = classifierModelFor(ctx).model;
		} catch (error) {
			return { block: true, reason: error instanceof Error ? error.message : String(error) };
		}

		// `event.input` is mutable and typed for built-ins; read a plain copy.
		const args = isToolCallEventType("bash", event) ? { command: event.input.command } : event.input;
		const prompt = buildClassifierPrompt(cfg, ctx.cwd, event.toolName, args, lastUserMessage(ctx));

		try {
			const text = await classify(ctx, model, prompt, ctx.signal);
			const verdict = parseVerdict(text);

			if (!verdict) {
				if (isReadOnly && !cfg.failClosed) return;
				return {
					block: true,
					reason: `Auto mode classifier returned an unparseable verdict; blocking "${event.toolName}" to be safe. Retry, or disable auto mode with /auto-mode off.`,
				};
			}
			if (verdict.decision === "block") {
				return { block: true, reason: `Auto mode blocked ${event.toolName}: ${verdict.reason || "flagged as risky."}` };
			}
			return; // allow
		} catch (error) {
			if (ctx.signal?.aborted) return { block: true, reason: "Auto mode classification aborted." };
			if (isReadOnly && !cfg.failClosed) return;
			return {
				block: true,
				reason: `Auto mode classifier error (${error instanceof Error ? error.message : String(error)}); blocking "${event.toolName}" to be safe.`,
			};
		}
	});

	pi.registerCommand("auto-mode", {
		description: "Auto mode: run without prompts, gating tool calls through a safety classifier",
		getArgumentCompletions: (prefix: string) => {
			const items = ["on", "off", "status", "config", "defaults"].map((value) => ({ value, label: value }));
			const filtered = items.filter((item) => item.value.startsWith(prefix.trim()));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();

			if (arg === "defaults") {
				ctx.ui.notify(JSON.stringify(DEFAULTS, null, 2), "info");
				return;
			}
			if (arg === "config") {
				ctx.ui.notify(JSON.stringify(loadConfig(ctx), null, 2), "info");
				return;
			}
			if (arg === "status") {
				let cls = "unavailable";
				try {
					const { family, model } = classifierModelFor(ctx);
					cls = `${model.provider}/${model.id} (${family})`;
				} catch (error) {
					cls = `unavailable — ${error instanceof Error ? error.message : String(error)}`;
				}
				ctx.ui.notify(`Auto mode is ${enabled ? "on" : "off"}. Classifier: ${cls}.`, "info");
				return;
			}

			const want = arg === "on" ? true : arg === "off" ? false : !enabled;
			if (want === enabled) {
				ctx.ui.notify(`Auto mode is already ${enabled ? "on" : "off"}.`, "info");
				return;
			}
			enabled = want;
			if (!enabled) {
				ctx.ui.notify("Auto mode disabled — tool calls run under pi's normal permissions.", "info");
				refreshStatus(ctx);
				return;
			}
			try {
				const { family, model } = classifierModelFor(ctx);
				ctx.ui.notify(`Auto mode enabled — classifier: ${model.provider}/${model.id} (${family}).`, "info");
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
			}
			refreshStatus(ctx);
		},
	});
}
