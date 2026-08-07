/**
 * Guards on the auto-mode rule text.
 *
 * Every case below corresponds to a shape the classifier blocked in practice
 * (project, host and branch names generalised). The rules are prose read by a
 * model, so these are not behavioural tests — they assert that the specific
 * carve-out which addresses each false positive is still present and has not
 * been edited away. Behaviour is verified by running the classifier.
 *
 *   cd pi/tests && npm install && npx vitest run
 */
import { describe, expect, it } from "vitest";

import { DEFAULTS, buildClassifierPrompt } from "../agent/extensions/auto-mode.js";

const ALL_RULES = [...DEFAULTS.environment, ...DEFAULTS.allow, ...DEFAULTS.soft_deny, ...DEFAULTS.hard_deny]
	.join("\n")
	.toLowerCase();

const prompt = (): string =>
	buildClassifierPrompt(
		{
			...DEFAULTS,
			trustedPaths: [],
			classifyReadOnlyTools: false,
			readOnlyBashFastPath: true,
			failClosed: true,
			enabled: false,
		},
		"/w/agent",
		["/w/agent", "/tmp"],
		"bash",
		{ command: "true" },
		"USER: go",
	).toLowerCase();

describe("the agent's own worktree is not treated as precious", () => {
	it("says resetting or cleaning the agent's own worktree is allowed", () => {
		expect(ALL_RULES).toContain("own worktree");
		expect(ALL_RULES).toMatch(/reflog|its commits stay/);
	});

	it("still protects a checkout somebody else is using", () => {
		expect(DEFAULTS.soft_deny.join(" ").toLowerCase()).toMatch(/shared box|another agent's worktree|own working copy/);
	});
});

describe("force-pushing the agent's own branch", () => {
	it("carves out the agent's own feature or PR branch", () => {
		const rewriting = DEFAULTS.soft_deny[0].toLowerCase();
		expect(rewriting).toContain("force-with-lease");
		expect(rewriting).toMatch(/own.*(feature|pull-request) branch/);
	});

	it("still denies force pushes to shared and default branches", () => {
		expect(DEFAULTS.soft_deny[0].toLowerCase()).toMatch(/default, shared or release branch/);
	});
});

describe("the user's own dev boxes", () => {
	it("names private and tailnet address ranges as the user's network", () => {
		expect(ALL_RULES).toContain("192.168");
		expect(ALL_RULES).toMatch(/tailnet/);
	});

	it("says the trusted-roots list is about paths, not a host allowlist", () => {
		expect(ALL_RULES).toMatch(/not a list of permitted hosts/);
	});

	it("allows shipping code and running benchmarks on them", () => {
		expect(DEFAULTS.allow.join(" ").toLowerCase()).toMatch(/dev boxes and running builds, tests, benchmarks/);
	});

	it("keeps credentials a separate question", () => {
		expect(DEFAULTS.allow.join(" ").toLowerCase()).toContain("moving *credentials* to them is a separate question");
	});
});

describe("environment reads", () => {
	it("scopes the env-dump hard deny to unfiltered output", () => {
		const envRule = DEFAULTS.hard_deny.find((r) => r.includes("whole process environment")) ?? "";
		expect(envRule.toLowerCase()).toContain("unfiltered");
		expect(envRule).toContain("env | grep");
		expect(envRule.toLowerCase()).toContain("do not extend this rule to filtered reads");
	});
});

describe("host housekeeping", () => {
	it("allows sudo package/swap/disk work on the agent's own machine", () => {
		expect(DEFAULTS.allow.join(" ").toLowerCase()).toMatch(/including with sudo/);
	});
});

describe("the prompt's 'not reasons to block' list", () => {
	const notReasons = () => prompt().split("these are not reasons to block:")[1]?.split("do block,")[0] ?? "";

	it("rejects 'unrelated to the stated task' as a safety property", () => {
		expect(notReasons()).toContain("not a safety property");
	});

	it("rejects unfamiliarity with a host", () => {
		expect(notReasons()).toContain("unfamiliarity is not evidence of a third party");
	});

	it("rejects speculation about what a command could destroy", () => {
		expect(notReasons()).toMatch(/speculation is not evidence/);
	});

	it("rejects authorization being out of the visible window", () => {
		expect(notReasons()).toMatch(/window, not the whole record/);
	});

	it("keeps the earlier carve-outs for location, pronouns and scary words", () => {
		const text = notReasons();
		expect(text).toContain("outside the working directory");
		expect(text).toMatch(/both of those things/);
		expect(text).toMatch(/"secret", "sensitive"/);
	});
});

describe("what must stay denied", () => {
	it("keeps third-party exfiltration and secret publishing as hard denies", () => {
		const hard = DEFAULTS.hard_deny.join(" ").toLowerCase();
		expect(hard).toContain("exfiltration to a third party");
		expect(hard).toContain("publishing secrets");
	});

	it("keeps production, curl-pipe-to-shell and database destruction as soft denies", () => {
		const soft = DEFAULTS.soft_deny.join(" ").toLowerCase();
		expect(soft).toContain("production changes");
		expect(soft).toMatch(/curl .* \| bash/);
		expect(soft).toMatch(/dropping or truncating databases/);
	});

	it("keeps the rule against weakening auto mode to get an action through", () => {
		expect(DEFAULTS.hard_deny.join(" ").toLowerCase()).toMatch(/weakening auto mode in order to get an action past it/);
	});
});
