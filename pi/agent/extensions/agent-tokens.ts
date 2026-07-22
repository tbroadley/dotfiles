/**
 * agent-tokens — injects static skill credentials into every pi agent's env.
 *
 * Reads ~/.pi/agent/agent-tokens.env (dotenv-style KEY=VALUE, one per line)
 * and sets each key in process.env if not already set. Agents run in-process
 * in the pirouette server and their bash tool inherits the server environment
 * (getShellEnv() spreads process.env), so every current and future agent gets
 * these credentials with no per-agent setup. Registers no tools/commands/
 * prompts, so agents are not otherwise notified of the capability.
 *
 * The env file is host-local and gitignored (never committed). To add/rotate a
 * credential: edit ~/.pi/agent/agent-tokens.env (0600) and restart the pi host
 * (on a pirouette systemd host: `sudo systemctl restart pirouette`).
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export default function agentTokens(): void {
	let raw: string;
	try {
		raw = readFileSync(join(homedir(), ".pi", "agent", "agent-tokens.env"), "utf8");
	} catch {
		return;
	}
	const injected: string[] = [];
	for (const line of raw.split("\n")) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith("#")) continue;
		const eq = trimmed.indexOf("=");
		if (eq <= 0) continue;
		const key = trimmed.slice(0, eq).trim();
		const value = trimmed.slice(eq + 1).trim();
		if (!key || !value || process.env[key]) continue;
		process.env[key] = value;
		injected.push(key);
	}
	if (injected.length > 0) {
		console.error(`[agent-tokens] injected into agent environment: ${injected.join(", ")}`);
	}
}
