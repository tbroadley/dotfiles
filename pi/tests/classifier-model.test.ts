/**
 * Which family auto mode picks the classifier from.
 *
 * The mapping used to be read off the API type, so a non-GPT model served over
 * an OpenAI-shaped API was handed the GPT classifier. The model id now decides
 * first, and the API/provider hints only get a say when the id reveals nothing
 * — a model whose id is an opaque alias keeps the classifier it always had
 * instead of becoming a hard error.
 *
 *   cd pi/tests && npm install && npx vitest run
 */
import { describe, expect, it } from "vitest";

import { detectFamily } from "../agent/extensions/auto-mode.js";

describe("detectFamily", () => {
	it("reads Claude ids as anthropic", () => {
		expect(detectFamily({ provider: "hawk", id: "claude-opus-5", api: "anthropic-messages" })).toBe("anthropic");
		expect(detectFamily({ provider: "anthropic", id: "claude-sonnet-4-5" })).toBe("anthropic");
	});

	it("reads gpt ids as openai", () => {
		expect(detectFamily({ provider: "hawk", id: "gpt-5.6-terra", api: "openai-completions" })).toBe("openai");
		expect(detectFamily({ provider: "openai", id: "gpt-5" })).toBe("openai");
	});

	it("lets the id win over the API the provider happens to speak", () => {
		// Served over the Anthropic Messages API, but it is still a GPT.
		expect(detectFamily({ provider: "hawk", id: "gpt-5.6-sol", api: "anthropic-messages" })).toBe("openai");
		expect(detectFamily({ provider: "hawk", id: "claude-opus-5", api: "openai-completions" })).toBe("anthropic");
	});

	it("falls back to the API type when the id says nothing", () => {
		expect(detectFamily({ provider: "hawk", id: "dog-no-refusals", api: "anthropic-messages" })).toBe("anthropic");
		expect(detectFamily({ provider: "hawk", id: "some-alias", api: "openai-responses" })).toBe("openai");
	});

	it("leaves a model in neither family undecided", () => {
		expect(detectFamily({ provider: "local", id: "llama-3", name: "Llama 3", api: "ollama" })).toBeUndefined();
		// "gpt" as part of a longer word is not the GPT family.
		expect(detectFamily({ provider: "x", id: "gptron-1", api: "custom" })).toBeUndefined();
		expect(detectFamily(undefined)).toBeUndefined();
	});
});
