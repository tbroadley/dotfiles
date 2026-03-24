import type { Model } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const HAWK_PROVIDER = "hawk";
const LOCAL_PROVIDER = "ollama";
const DEFAULT_HAWK_MODEL_ID = "gpt-5.4";
const NO_HAWK_MODEL_MESSAGE = "Restricted model mode is enabled, but no Hawk models are available. Run /login hawk.";

function getPreferredHawkModel(ctx: ExtensionContext): Model<any> | undefined {
	const defaultModel = ctx.modelRegistry.find(HAWK_PROVIDER, DEFAULT_HAWK_MODEL_ID);
	if (defaultModel && defaultModel.provider === HAWK_PROVIDER) {
		return defaultModel;
	}

	for (const model of ctx.modelRegistry.getAvailable()) {
		if (model.provider === HAWK_PROVIDER) {
			return model;
		}
	}

	for (const model of ctx.modelRegistry.getAll()) {
		if (model.provider === HAWK_PROVIDER) {
			return model;
		}
	}

	return undefined;
}

export default function (pi: ExtensionAPI): void {
	let isEnforcing = false;

	async function enforceHawk(ctx: ExtensionContext): Promise<void> {
		if (isEnforcing) return;
		if (ctx.model?.provider === HAWK_PROVIDER || ctx.model?.provider === LOCAL_PROVIDER) return;

		const hawkModel = getPreferredHawkModel(ctx);
		if (!hawkModel) {
			throw new Error(NO_HAWK_MODEL_MESSAGE);
		}

		isEnforcing = true;
		try {
			const changed = await pi.setModel(hawkModel);
			if (!changed) {
				throw new Error(NO_HAWK_MODEL_MESSAGE);
			}
		} finally {
			isEnforcing = false;
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		try {
			await enforceHawk(ctx);
		} catch (error) {
			ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		await enforceHawk(ctx);
	});

	pi.on("model_select", async (event, ctx) => {
		if (isEnforcing) return;
		if (event.model.provider === HAWK_PROVIDER || event.model.provider === LOCAL_PROVIDER) return;

		await enforceHawk(ctx);
		ctx.ui.notify("Restricted model mode reverted the selected model.", "warning");
	});
}
