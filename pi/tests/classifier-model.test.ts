/**
 * Which model auto mode picks to judge tool calls.
 *
 * Two properties matter and neither is obvious from the mapping table. The
 * family comes from the model *id*, not from the API the provider speaks, so a
 * non-GPT model served over an OpenAI-shaped API is not handed the GPT
 * classifier. And an unrecognised model does not turn auto mode into a wall:
 * it falls back to Sonnet, the model the rule text is tuned against, rather
 * than erroring out and blocking every mutating tool call.
 *
 *   cd pi/tests && npm install && npx vitest run
 */
import { describe, expect, it } from "vitest";

import { classifierFamilyFor, detectFamily } from "../agent/extensions/auto-mode.js";

describe("detectFamily", () => {
	it("reads Claude ids as anthropic", () => {
		expect(detectFamily({ provider: "hawk", id: "claude-opus-5" })).toBe("anthropic");
		expect(detectFamily({ provider: "anthropic", id: "claude-sonnet-4-5" })).toBe("anthropic");
	});

	it("reads gpt ids as openai", () => {
		expect(detectFamily({ provider: "hawk", id: "gpt-5.6-terra" })).toBe("openai");
		expect(detectFamily({ provider: "openai", id: "gpt-5" })).toBe("openai");
	});

	it("leaves everything else undecided", () => {
		expect(detectFamily({ provider: "hawk", id: "gemini-3-pro" })).toBeUndefined();
		expect(detectFamily({ provider: "hawk", id: "dog-no-refusals" })).toBeUndefined();
		// "gpt" as part of a longer word is not the GPT family.
		expect(detectFamily({ provider: "x", id: "gptron-1" })).toBeUndefined();
		expect(detectFamily(undefined)).toBeUndefined();
	});
});

describe("classifierFamilyFor", () => {
	it("keeps each recognised family on its own classifier", () => {
		expect(classifierFamilyFor({ provider: "hawk", id: "claude-opus-5" })).toBe("anthropic");
		expect(classifierFamilyFor({ provider: "hawk", id: "gpt-5.6-sol" })).toBe("openai");
	});

	it("falls back to the anthropic classifier for anything else", () => {
		expect(classifierFamilyFor({ provider: "hawk", id: "gemini-3-pro" })).toBe("anthropic");
		expect(classifierFamilyFor(undefined)).toBe("anthropic");
	});
});
