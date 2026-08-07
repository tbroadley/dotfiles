/**
 * Tests for auto mode's per-agent on/off overrides.
 *
 * Auto mode used to keep `enabled` in a module-level variable. A host that runs
 * many agents inside one process loads each extension exactly once, so that
 * variable was a single switch for the whole instance: turning auto mode off in
 * one chat disabled the classifier for every other agent, and the next agent's
 * session_start turned it back on for all of them. State is now keyed by the
 * agent's working directory and persisted, so a toggle affects one chat only.
 *
 *   cd pi/tests && npm install && npx vitest run
 */
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { readOverrides } from "../agent/extensions/auto-mode.js";

let dir: string;
let file: string;

beforeEach(() => {
	dir = mkdtempSync(join(tmpdir(), "auto-mode-test-"));
	file = join(dir, "auto-mode-agents.json");
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("readOverrides", () => {
	it("returns an empty map when the file does not exist", () => {
		expect(readOverrides(join(dir, "nope.json"))).toEqual({});
	});

	it("returns an empty map for malformed JSON rather than throwing", () => {
		writeFileSync(file, "{ not json");
		expect(readOverrides(file)).toEqual({});
	});

	it("reads per-agent booleans keyed by worktree path", () => {
		writeFileSync(file, JSON.stringify({ "/w/a": false, "/w/b": true }));
		expect(readOverrides(file)).toEqual({ "/w/a": false, "/w/b": true });
	});

	it("ignores non-boolean values so a hand-edited file cannot open the gate", () => {
		writeFileSync(file, JSON.stringify({ "/w/a": "off", "/w/b": 0, "/w/c": null, "/w/d": false }));
		expect(readOverrides(file)).toEqual({ "/w/d": false });
	});
});

describe("override precedence", () => {
	// Mirrors resolveEnabled(): flag > per-agent override > config default.
	const resolve = (opts: {
		flag?: boolean;
		override?: boolean;
		configEnabled: boolean | "pirouette";
		underPirouette: boolean;
	}): boolean => {
		if (opts.flag) return true;
		if (typeof opts.override === "boolean") return opts.override;
		return opts.configEnabled === true || (opts.configEnabled === "pirouette" && opts.underPirouette);
	};

	it("an agent override beats the global default in both directions", () => {
		expect(resolve({ override: false, configEnabled: "pirouette", underPirouette: true })).toBe(false);
		expect(resolve({ override: true, configEnabled: false, underPirouette: true })).toBe(true);
	});

	it("agents without an override still follow the global default", () => {
		expect(resolve({ configEnabled: "pirouette", underPirouette: true })).toBe(true);
		expect(resolve({ configEnabled: "pirouette", underPirouette: false })).toBe(false);
		expect(resolve({ configEnabled: false, underPirouette: true })).toBe(false);
	});

	it("an explicit --auto-mode flag wins over an off override", () => {
		expect(resolve({ flag: true, override: false, configEnabled: false, underPirouette: false })).toBe(true);
	});

	it("turning one agent off leaves its neighbours alone", () => {
		writeFileSync(file, JSON.stringify({ "/w/quiet": false }));
		const overrides = readOverrides(file);
		const enabledFor = (cwd: string) =>
			resolve({ override: overrides[cwd], configEnabled: "pirouette", underPirouette: true });
		expect(enabledFor("/w/quiet")).toBe(false);
		expect(enabledFor("/w/other")).toBe(true);
		expect(enabledFor("/w/another")).toBe(true);
	});
});

describe("override file round-trip", () => {
	// Mirrors writeOverride(): merge into the existing map, delete on undefined.
	const write = (key: string, value: boolean | undefined) => {
		const all = readOverrides(file);
		if (value === undefined) delete all[key];
		else all[key] = value;
		writeFileSync(file, `${JSON.stringify(all, null, 2)}\n`);
	};

	it("keeps other agents' entries when one is toggled", () => {
		write("/w/a", false);
		write("/w/b", true);
		expect(readOverrides(file)).toEqual({ "/w/a": false, "/w/b": true });
	});

	it("clearing one entry leaves the rest intact", () => {
		write("/w/a", false);
		write("/w/b", false);
		write("/w/a", undefined);
		expect(readOverrides(file)).toEqual({ "/w/b": false });
	});

	it("writes valid, human-editable JSON", () => {
		write("/w/a", false);
		expect(() => JSON.parse(readFileSync(file, "utf8"))).not.toThrow();
	});
});
