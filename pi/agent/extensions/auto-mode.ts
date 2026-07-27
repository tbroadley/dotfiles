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
 * The trust boundary is *the user's environment*, not the current working
 * directory. Sibling git worktrees, other local clones, /tmp scratch space and
 * the user's own dev boxes are all inside it; third-party services, unknown
 * hosts and production systems are outside it. Directory location alone is
 * never a reason to block — only irreversible or externally-aimed effects are.
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
 *     "trustedPaths": ["/data/scratch", "/mnt/work"],  // extra roots treated as "this machine"
 *     "classifyReadOnlyTools": false,   // classify read-only tools too (default: skip them)
 *     "readOnlyBashFastPath": true,     // skip the classifier for provably read-only shell (default: true)
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
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

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

// Tools that only read state (or mutate ephemeral session state). They are
// allowed without a classifier call unless `classifyReadOnlyTools` is set.
// pi's built-in read-only tools are read/ls/grep/find; manage_todo_list only
// touches the in-session todo list. The mutating built-ins bash/write/edit and
// any unknown custom tool are always classified.
const READ_ONLY_TOOLS = new Set(["read", "ls", "grep", "find", "manage_todo_list"]);

// ---------------------------------------------------------------------------
// Read-only shell detection
//
// The largest observed source of false positives was read-only inspection
// (`git log`, `gh pr checks`, `grep`) in a sibling worktree getting blocked as
// "outside the trusted working directory". A command that provably cannot
// mutate or transmit anything doesn't need a judgement call at all, so we skip
// the classifier for it. Deliberately conservative: anything unrecognised
// falls through to the classifier, which only costs a round-trip.
// ---------------------------------------------------------------------------

const READ_ONLY_BASH = new Set([
	"cd", "pwd", "ls", "dir", "cat", "bat", "head", "tail", "wc", "nl", "cut", "sort", "uniq",
	"tr", "column", "echo", "printf", "true", "false", "basename", "dirname", "realpath", "readlink",
	"stat", "file", "tree", "du", "df", "which", "type", "whoami", "id", "hostname", "uname",
	"date", "ps", "uptime", "free", "sleep", "seq",
	"grep", "egrep", "fgrep", "rg", "ag", "ack", "fd", "find", "diff", "cmp",
	"md5sum", "sha1sum", "sha256sum", "jq", "yq", "awk", "sed",
]);

/** Verbs that make an otherwise-ambiguous CLI read-only. */
const READ_ONLY_SUBCOMMANDS: Record<string, Set<string>> = {
	git: new Set([
		"status", "diff", "log", "show", "blame", "branch", "tag", "remote", "describe",
		"rev-parse", "rev-list", "ls-files", "ls-tree", "ls-remote", "shortlog", "whatchanged",
		"cat-file", "grep", "worktree", "stash", "reflog", "merge-base", "name-rev", "count-objects",
	]),
	gh: new Set(["pr", "issue", "run", "repo", "api", "auth", "search", "release", "workflow", "label"]),
	npm: new Set(["ls", "list", "view", "info", "outdated", "why", "root", "prefix"]),
	docker: new Set(["ps", "images", "logs", "inspect", "version", "info"]),
	kubectl: new Set(["get", "describe", "logs", "top", "version", "api-resources"]),
	uv: new Set(["tree"]),
	cargo: new Set(["tree", "metadata"]),
};

/** Third-level verbs, where the noun alone doesn't say read vs write. */
const READ_ONLY_SUBSUBCOMMANDS: Record<string, Set<string>> = {
	"gh pr": new Set(["view", "list", "diff", "checks", "status"]),
	"gh issue": new Set(["view", "list", "status"]),
	"gh run": new Set(["view", "list", "watch"]),
	"gh repo": new Set(["view", "list"]),
	"gh release": new Set(["view", "list"]),
	"gh workflow": new Set(["view", "list"]),
	"gh label": new Set(["list"]),
	"gh search": new Set(["prs", "issues", "repos", "code", "commits"]),
	"gh auth": new Set(["status"]),
	"gh api": new Set(), // special-cased: GET-only
	"git worktree": new Set(["list"]),
	"git stash": new Set(["list", "show"]),
	"git branch": new Set([
		"--show-current", "--list", "-l", "-v", "-vv", "-a", "-r", "--all", "--remotes",
		"--contains", "--merged", "--no-merged", "--format", "--points-at", "--sort",
	]),
	"git tag": new Set(["-l", "--list", "-n", "--contains", "--points-at", "--sort", "--format"]),
	"git remote": new Set(["-v", "--verbose", "show", "get-url"]),
};

/** Bare `<cmd> <verb>` with no further args is a listing / help screen. */
const BARE_IS_A_LISTING = new Set([
	"git remote", "git branch", "git tag", "git worktree",
	"gh pr", "gh issue", "gh run", "gh repo", "gh release", "gh workflow", "gh label",
	"gh search", "gh auth",
]);

/** Flags that consume the following token, so we can find the real verb. */
const VALUE_FLAGS = new Set(["-C", "-c", "--git-dir", "--work-tree", "-R", "--repo", "-L", "--limit"]);

/** `2>&1`, `>/dev/null`, `2>/dev/null` are noise, not redirection to a file. */
const NULL_REDIRECT = /\s*\d?>>?\s*(&\d|\/dev\/null)/g;

/** Anything that can write, transmit, or escape the read-only assumption. */
const SHELL_ESCAPES = /[><`]|\$\(|\bsudo\b|\beval\b|\bexec\b|\bsource\b/;

/**
 * Split a command on *unquoted* shell operators.
 *
 * Quote awareness matters: `grep -nE 'from x|import y' file` is one read-only
 * segment, not two nonsense ones. Returns the segments plus everything that
 * appeared outside quotes, so redirection/`sudo`/`eval` scanning ignores
 * characters that are really just part of a regex or a message.
 * Returns undefined on unbalanced quoting — then the classifier decides.
 */
function splitShell(command: string): { segments: string[]; unquoted: string } | undefined {
	const segments: string[] = [];
	let unquoted = "";
	let current = "";
	let quote: '"' | "'" | undefined;
	for (let i = 0; i < command.length; i++) {
		const ch = command[i];
		if (quote) {
			if (ch === "\\" && quote === '"') {
				current += ch + (command[++i] ?? "");
				continue;
			}
			current += ch;
			if (ch === quote) quote = undefined;
			continue;
		}
		if (ch === "'" || ch === '"') {
			quote = ch;
			current += ch;
			continue;
		}
		if (ch === "\\") {
			current += ch + (command[++i] ?? "");
			continue;
		}
		unquoted += ch;
		if (ch === "\n" || ch === ";" || ch === "|" || ch === "&") {
			if ((ch === "|" || ch === "&") && command[i + 1] === ch) {
				unquoted += ch;
				i += 1;
			}
			segments.push(current);
			current = "";
			continue;
		}
		current += ch;
	}
	if (quote) return undefined;
	segments.push(current);
	return { segments: segments.map((s) => s.trim()).filter(Boolean), unquoted };
}

function nextWord(tokens: string[], start: number): { word?: string; index: number } {
	let i = start;
	while (i < tokens.length) {
		const t = tokens[i];
		if (t.startsWith("-")) {
			i += VALUE_FLAGS.has(t) ? 2 : 1;
			continue;
		}
		return { word: t, index: i };
	}
	return { index: i };
}

function isReadOnlySegment(segment: string): boolean {
	const tokens = segment.split(/\s+/).filter((t) => t && !/^[A-Za-z_][A-Za-z0-9_]*=/.test(t));
	const head = tokens[0];
	if (!head) return false;

	// Narrow forms only.
	if (head === "sed" && !tokens.some((t) => t === "-n" || /^-[a-zA-Z]*n$/.test(t))) return false;
	if (head === "find" && /(^|\s)-(delete|exec|execdir|ok|okdir|fls|fprint)\b/.test(segment)) return false;
	if (head === "yq" && tokens.includes("-i")) return false;
	if (READ_ONLY_BASH.has(head)) return true;

	const subs = READ_ONLY_SUBCOMMANDS[head];
	if (!subs) return false;
	const { word: verb, index: verbIndex } = nextWord(tokens, 1);
	if (!verb || !subs.has(verb)) return false;

	const key = `${head} ${verb}`;
	const deeper = READ_ONLY_SUBSUBCOMMANDS[key];
	if (!deeper) return true;

	if (key === "gh api") {
		// `gh api` defaults to GET; -X/--method/-f/--field/--input make it write.
		return !/(^|\s)(-X|--method|-f|--field|-F|--raw-field|--input)(\s|=)/.test(segment);
	}

	const rest = tokens.slice(verbIndex + 1);
	if (rest.length === 0) return BARE_IS_A_LISTING.has(key);
	// Accept either a read-only sub-verb (`gh pr view`) or a read-only flag
	// (`git branch --show-current`), and reject destructive flags outright.
	if (key === "git branch" || key === "git tag") {
		if (rest.some((t) => /^(-d|-D|--delete|-m|-M|--move|--copy|-f|--force|-u|--set-upstream-to|--unset-upstream|--edit-description)$/.test(t))) {
			return false;
		}
	}
	return rest.some((t) => deeper.has(t) || deeper.has(t.split("=")[0]));
}

export function isReadOnlyBash(command: string): boolean {
	if (!command) return false;
	const split = splitShell(command.replace(NULL_REDIRECT, " "));
	if (!split) return false;
	const { segments, unquoted } = split;
	if (SHELL_ESCAPES.test(unquoted) || unquoted.includes("<<") || unquoted.includes("<(")) return false;
	if (segments.length === 0) return false;
	return segments.every(isReadOnlySegment);
}

// ---------------------------------------------------------------------------
// Trusted filesystem roots
// ---------------------------------------------------------------------------

/**
 * Concrete filesystem roots that count as "this machine, the user's own work".
 *
 * The previous prompt described trust purely as "the working directory", so the
 * classifier blocked every sibling worktree, sibling clone and /tmp scratch
 * path. Naming the real roots gives it something factual to check instead of
 * inferring intent from a path string.
 */
export function trustedRoots(cwd: string, extra: string[] = []): string[] {
	const roots = new Set<string>();
	const add = (p: string | undefined): void => {
		if (p && p.trim()) roots.add(resolve(p.trim()));
	};
	add(cwd);
	add(tmpdir());
	add("/tmp");
	// Every worktree of a repository shares one common git dir, so its parent
	// covers the repo and all of its worktrees.
	try {
		const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
			timeout: 2000,
		}).trim();
		if (common) add(dirname(common));
	} catch {
		/* not a git repo, or git unavailable */
	}
	// Pirouette lays out every project's repo + its agent worktrees under its data dir.
	const dataDir = process.env.PIROUETTE_DATA_DIR;
	if (dataDir) {
		add(join(dataDir, "worktrees"));
		add(join(dataDir, "repos"));
	}
	for (const p of extra) add(p);
	return [...roots];
}

const rootsCache = new Map<string, string[]>();
function cachedTrustedRoots(cwd: string, extra: string[]): string[] {
	const key = `${cwd}\u0000${extra.join("\u0000")}`;
	let value = rootsCache.get(key);
	if (!value) {
		value = trustedRoots(cwd, extra);
		rootsCache.set(key, value);
	}
	return value;
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

interface AutoModeConfig {
	environment: string[];
	allow: string[];
	soft_deny: string[];
	hard_deny: string[];
	trustedPaths: string[];
	classifyReadOnlyTools: boolean;
	readOnlyBashFastPath: boolean;
	failClosed: boolean;
	/** Turn auto mode on by default: true = host-wide, "pirouette" = only under the pirouette server. */
	enabled: boolean | "pirouette";
}

export const DEFAULTS = {
	environment: [
		"The local machine the agent runs on is trusted. That includes the working directory, sibling git worktrees and other local clones of the same or related repositories, other project checkouts on this machine, scratch space (/tmp, $TMPDIR, caches) and the user's home directory.",
		"The repositories the user works in — the working repo, its remotes, and any other repository the user has referred to in this conversation — are trusted, together with normal collaboration on them (branches, pushes, pull requests, reviews, CI).",
		"Development and staging infrastructure the user owns (their own dev boxes, sandboxes, scratch buckets, ephemeral VMs) is part of the user's environment, not a third party.",
		"'External' means somewhere the user does not control: third-party APIs and SaaS, public paste/gist services, unknown hosts, public repositories, and production systems. Being outside the working directory but still on this machine, or in another of the user's repositories, is NOT external.",
	],
	allow: [
		"Routine development anywhere on this machine: reading, editing, creating and moving files; building; running tests, linters, formatters, type checkers; scratch scripts in /tmp.",
		"Read-only inspection of anything local (status, diff, log, ls, cat, grep, gh pr view/checks, reading logs and session files), regardless of directory.",
		"Working in a sibling worktree, another checkout, or a second repository on this machine, including committing and pushing there — multi-repo and multi-worktree work is the normal mode of operation here.",
		"Package installs from a project's normal registry (npm, PyPI, cargo, apt, uv, ...), and installing standard developer tooling on this machine or on the user's own dev boxes.",
		"Committing, pushing to any branch (including default branches), opening/updating/merging pull requests and commenting on them, as long as history is not rewritten.",
		"Cleaning up the user's own ephemeral dev resources (stopping or terminating scratch VMs, deleting temp dirs, tearing down sandboxes) when the user has asked for cleanup or authorized it.",
		"Reading and editing the agent's own configuration, extensions and this classifier's own rules when the user has asked for that work.",
	],
	soft_deny: [
		"Git history rewriting: force pushing, deleting remote branches/tags/releases, rewriting already-pushed history, or amending already-pushed commits.",
		"Irrecoverable deletion of work the user has not backed up: `rm -rf` over a home directory, a whole repository or broad wildcards; `git reset --hard` / `git clean -fdx` that would discard uncommitted work the agent did not itself create.",
		"Production changes: deploys, `terraform apply`/`destroy` against prod, and write access to hosts, clusters or namespaces whose name marks them production (`prod`, `production`, `release`). Read-only queries against production are fine.",
		"Piping remote content straight into a shell (`curl … | bash`) from a source that is not a well-known vendor installer, or otherwise executing unreviewed downloaded code.",
		"Dropping or truncating databases, or running migrations against a shared or production database.",
	],
	hard_deny: [
		"Exfiltration to a third party: sending repository contents, secrets, credentials, or personal/regulated data to a destination the user does not control (third-party APIs, public paste/gist services, unknown hosts, public repositories).",
		"Publishing secrets: committing them, printing them into a shared channel, or otherwise exposing private keys, tokens, .env values or cloud credentials somewhere they become durably visible to others. Moving the user's own credentials between the user's own machines at their request is not this.",
		"Weakening auto mode in order to get an action past it: turning the classifier off, editing its rules, or routing around it mid-task so that a previously blocked call succeeds. Reading or inspecting auto mode, and deliberately improving it as the task the user actually asked for, are allowed.",
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
	const rawTrusted = pick("trustedPaths");
	return {
		environment: spliceDefaults(pick("environment"), DEFAULTS.environment),
		allow: spliceDefaults(pick("allow"), DEFAULTS.allow),
		soft_deny: spliceDefaults(pick("soft_deny"), DEFAULTS.soft_deny),
		hard_deny: spliceDefaults(pick("hard_deny"), DEFAULTS.hard_deny),
		trustedPaths: Array.isArray(rawTrusted) ? rawTrusted.filter((p): p is string => typeof p === "string") : [],
		classifyReadOnlyTools: bool("classifyReadOnlyTools", false),
		readOnlyBashFastPath: bool("readOnlyBashFastPath", true),
		failClosed: bool("failClosed", true),
		enabled,
	};
}

function bullets(items: string[]): string {
	return items.map((i) => `- ${i}`).join("\n");
}

// ---------------------------------------------------------------------------
// Intent
// ---------------------------------------------------------------------------

/**
 * A short excerpt of the recent conversation, used as the "explicit intent"
 * signal.
 *
 * Previously only the single most recent user message was passed, which meant
 * that a confirmation like "Yes, you can continue pushing changes into that
 * work tree" or "Yep, you have my permission to do both of those things" —
 * whose referent lives in earlier turns — read as vague, and the classifier
 * blocked the very thing the user had just authorized. Including the
 * surrounding turns lets it resolve those references.
 */
export function recentConversation(ctx: ExtensionContext, maxTurns = 8, maxChars = 5000): string {
	const entries = ctx.sessionManager.getEntries();
	const turns: string[] = [];
	for (let i = entries.length - 1; i >= 0 && turns.length < maxTurns; i--) {
		const e: any = entries[i];
		if (e?.type !== "message") continue;
		const role = e.message?.role;
		if (role !== "user" && role !== "assistant") continue;
		const text = (e.message.content ?? [])
			.filter((c: any) => c?.type === "text")
			.map((c: any) => c.text)
			.join("\n")
			.trim();
		if (!text) continue;
		// Don't feed our own block notices back in as if they were user intent.
		if (text.startsWith("Auto mode blocked") || text.startsWith("Auto mode classifier")) continue;
		turns.push(`${role === "user" ? "USER" : "ASSISTANT"}: ${text.slice(0, 1500)}`);
	}
	turns.reverse();
	let out = turns.join("\n\n");
	if (out.length > maxChars) out = `… (earlier turns omitted)\n\n${out.slice(out.length - maxChars)}`;
	return out;
}

export function buildClassifierPrompt(
	cfg: AutoModeConfig,
	cwd: string,
	roots: string[],
	toolName: string,
	args: unknown,
	conversation: string,
): string {
	let argsText: string;
	try {
		argsText = JSON.stringify(args, null, 2);
	} catch {
		argsText = String(args);
	}
	if (argsText.length > 6000) argsText = `${argsText.slice(0, 6000)}\n… (truncated)`;

	return `You are the auto-mode safety gate for an autonomous coding agent. The user has deliberately chosen to run this agent unattended, so you are the only check — but they are also relying on it to make progress. A wrong block stalls their work and costs them a round-trip, so block only when you can name a concrete, irreversible harm. When a call is reversible and stays inside the user's environment, allow it.

Decide in this order:
1. HARD DENY — block unconditionally. User intent cannot override these.
${bullets(cfg.hard_deny)}
2. SOFT DENY — block unless the recent conversation shows the user asked for or agreed to this kind of action.
${bullets(cfg.soft_deny)}
3. ALLOW — these are explicitly fine even if they superficially resemble a soft deny.
${bullets(cfg.allow)}
4. Otherwise ALLOW. The default is allow; a call must match a hard or soft deny to be blocked.

The user's trusted environment:
${bullets(cfg.environment)}

Trusted filesystem roots on this machine (paths under any of these are local, internal work — never "external"):
${bullets(roots)}

These are NOT reasons to block:
- The path is outside the working directory but still on this machine, in another worktree, another clone, /tmp, or the user's home.
- The action targets a different repository the user has been discussing in this conversation.
- The user's most recent message is short, off-topic, an apology, a correction, or simply absent. Lack of a fresh instruction is not a reason to block a routine action; the agent is expected to keep working.
- The authorization is phrased with a pronoun ("do that", "both of those things", "that work tree", "go ahead"). Resolve it against the conversation below — a confirmation of a plan the assistant just described IS explicit authorization for that plan.
- The command merely mentions words like "secret", "sensitive", "credentials", "prod" or "token" (in a flag name, a path, a variable, a grep pattern) without actually transmitting such data somewhere external.
- You are uncertain. For a reversible, local action, uncertainty resolves to allow.

Do block, regardless of how routine the surrounding task is, when the effect is irreversible and unrequested, or aimed at a destination outside the user's environment.

Working directory: ${cwd || "(unknown)"}

Recent conversation (most recent last; use it to resolve what the user has asked for and authorized):
"""
${conversation || "(none)"}
"""

Tool call to judge:
  tool: ${toolName}
  arguments:
${argsText}

Respond with ONLY a single JSON object, no prose, no code fences. Write the reason first, then let the decision follow from it. If you block, the reason must name the specific irreversible or external effect:
{"reason": "<one concise sentence>", "decision": "allow" | "block"}`;
}

interface Verdict {
	decision: "allow" | "block";
	reason: string;
}

/**
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

		// `event.input` is mutable and typed for built-ins; read a plain copy.
		const isBash = isToolCallEventType("bash", event);
		const args = isBash ? { command: event.input.command } : event.input;

		// Provably read-only shell needs no judgement call. This is what keeps
		// `git log` / `gh pr checks` / `grep` in a sibling worktree from being
		// blocked as "outside the trusted working directory".
		if (isBash && cfg.readOnlyBashFastPath && !cfg.classifyReadOnlyTools && isReadOnlyBash(event.input.command)) {
			return;
		}

		let model: Model<any>;
		try {
			model = classifierModelFor(ctx).model;
		} catch (error) {
			return { block: true, reason: error instanceof Error ? error.message : String(error) };
		}

		const roots = cachedTrustedRoots(ctx.cwd, cfg.trustedPaths);
		const prompt = buildClassifierPrompt(cfg, ctx.cwd, roots, event.toolName, args, recentConversation(ctx));

		try {
			// One retry on an unparseable verdict: a malformed response is a
			// formatting flake, not a safety signal, and blocking on it was a
			// recurring source of spurious stalls.
			let verdict: Verdict | undefined;
			for (let attempt = 0; attempt < 2 && !verdict; attempt++) {
				if (ctx.signal?.aborted) return { block: true, reason: "Auto mode classification aborted." };
				verdict = parseVerdict(await classify(ctx, model, prompt, ctx.signal));
			}

			if (!verdict) {
				if (!cfg.failClosed) return;
				return {
					block: true,
					reason: `Auto mode classifier returned an unparseable verdict twice; blocking "${event.toolName}" to be safe. Retry, or disable auto mode with /auto-mode off.`,
				};
			}
			if (verdict.decision === "block") {
				return {
					block: true,
					reason:
						`Auto mode blocked ${event.toolName}: ${verdict.reason || "flagged as risky."}` +
						` If this is a false positive, tell the user what you were trying to do and why it is safe — ` +
						`they can authorize it explicitly or run /auto-mode off.`,
				};
			}
			return; // allow
		} catch (error) {
			if (ctx.signal?.aborted) return { block: true, reason: "Auto mode classification aborted." };
			if (!cfg.failClosed) return;
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
				const cfg = loadConfig(ctx);
				ctx.ui.notify(
					JSON.stringify({ ...cfg, resolvedTrustedRoots: cachedTrustedRoots(ctx.cwd, cfg.trustedPaths) }, null, 2),
					"info",
				);
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
