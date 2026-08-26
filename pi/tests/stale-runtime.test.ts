/**
 * Auto mode must survive a stale shared extension runtime.
 *
 * Pirouette runs every agent in one process behind one extension runtime, and
 * pi marks that runtime stale for good as soon as any single session is
 * disposed (`pru stop`, `/new`, archive, handoff). `pi.getFlag` asserts the
 * runtime is active before answering, so the `tool_call` gate — which calls it
 * for any agent it hasn't seen yet — started throwing
 *
 *   This extension ctx is stale after session replacement or reload. …
 *
 * in place of every tool result. One stopped chat wedged every agent launched
 * afterwards on its first bash call until the server was restarted.
 *
 * The gate must degrade to the persisted override / config default instead —
 * and must degrade CLOSED, never silently letting tool calls through.
 *
 *   cd pi/tests && npm install && npx vitest run
 */
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import autoMode from "../agent/extensions/auto-mode.js";

const STALE = new Error(
	"This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload().",
);

type Handler = (event: unknown, ctx: unknown) => Promise<{ block?: boolean; reason?: string } | undefined>;

let dataDir: string;
let cwd: string;

/** Load the extension with a `pi` whose action methods behave like pi's do on
 *  a runtime some other agent's disposal already poisoned. */
function loadAutoMode(getFlag: () => unknown): Handler {
	const handlers = new Map<string, Handler>();
	const pi = {
		registerFlag: () => {},
		registerCommand: () => {},
		registerTool: () => {},
		on: (event: string, handler: Handler) => handlers.set(event, handler),
		getFlag,
	};
	autoMode(pi as never);
	const onToolCall = handlers.get("tool_call");
	expect(onToolCall).toBeDefined();
	return onToolCall!;
}

/** A ctx whose model is neither Anthropic nor OpenAI. Auto mode blocks those
 *  with a specific message *after* deciding the gate is on, which lets us
 *  observe the gate without calling a classifier over the network. */
function fakeCtx() {
	return {
		cwd,
		model: { provider: "local", id: "llama-3", name: "Llama 3", api: "ollama" },
		isProjectTrusted: () => false,
		hasUI: false,
		ui: { setStatus: () => {}, notify: () => {} },
		sessionManager: { getEntries: () => [] },
		signal: undefined,
	};
}

const toolCall = { type: "tool_call", toolCallId: "1", toolName: "bash", input: { command: "rm -rf /srv/data" } };

beforeEach(() => {
	dataDir = mkdtempSync(join(tmpdir(), "auto-mode-stale-"));
	cwd = join(dataDir, "worktrees", "proj", "agent");
	mkdirSync(join(dataDir, "state"), { recursive: true });
	mkdirSync(cwd, { recursive: true });
	// Pin the per-agent override so the developer's own ~/.pi config can't
	// decide this test's outcome.
	writeFileSync(join(dataDir, "state", "auto-mode-agents.json"), JSON.stringify({ [cwd]: true }));
	process.env.PIROUETTE_DATA_DIR = dataDir;
});

afterEach(() => {
	delete process.env.PIROUETTE_DATA_DIR;
	rmSync(dataDir, { recursive: true, force: true });
});

describe("the tool_call gate with a stale extension runtime", () => {
	it("keeps gating instead of failing the tool call", async () => {
		const onToolCall = loadAutoMode(() => {
			throw STALE;
		});

		const result = await onToolCall(toolCall, fakeCtx());

		expect(result?.block).toBe(true);
		expect(result?.reason).not.toMatch(/stale/i);
		expect(result?.reason).toMatch(/only Anthropic and OpenAI/);
	});

	it("does not let the stale error escape as a tool result", async () => {
		const onToolCall = loadAutoMode(() => {
			throw STALE;
		});

		await expect(onToolCall(toolCall, fakeCtx())).resolves.toBeDefined();
	});

	it("still honours a per-agent 'off' override", async () => {
		writeFileSync(join(dataDir, "state", "auto-mode-agents.json"), JSON.stringify({ [cwd]: false }));
		const onToolCall = loadAutoMode(() => {
			throw STALE;
		});

		expect(await onToolCall(toolCall, fakeCtx())).toBeUndefined();
	});
});

describe("the tool_call gate with a healthy extension runtime", () => {
	it("still lets --auto-mode force the gate on", async () => {
		writeFileSync(join(dataDir, "state", "auto-mode-agents.json"), JSON.stringify({ [cwd]: false }));
		const onToolCall = loadAutoMode(() => true);

		const result = await onToolCall(toolCall, fakeCtx());

		expect(result?.block).toBe(true);
		expect(result?.reason).toMatch(/only Anthropic and OpenAI/);
	});
});
