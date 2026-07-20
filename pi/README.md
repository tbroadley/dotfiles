# pi configuration

Config for [pi](https://github.com/earendil-works/pi-coding-agent) lives in
`pi/agent/` and is deployed by `install.sh`:

- `settings.json` — merged onto any existing local settings (dotfiles keys win,
  local-only keys like `defaultModel` preserved).
- `models.json` — copied to `~/.pi/agent/models.json` **only when no local file
  exists**. It is never overwritten or merged, so a local `models.json` may hold
  additional (e.g. private/internal) model entries that are not committed here.
- `AGENTS.md` — symlinked.
- `extensions/hawk-only.ts` — restricts model selection to the `hawk` provider.

## Hawk provider

The `hawk` provider comes from the **`tbroadley/pi-hawk-provider` fork**, which
adds user-defined "extra" models on top of the discovered permitted-model list.
(Upstream `neevparikh/pi-hawk-provider` lacks that feature until the fork's PR
lands; `install.sh` installs the fork and removes the upstream package if
present.)

### Adding an extra model

The provider only auto-lists models that exist in pi-ai's built-in
`openai`/`anthropic` catalogs. Anything else (e.g. OpenRouter-routed models)
must be declared under `providers.hawk.extraModels`:

```jsonc
{
  "id": "openrouter/moonshotai/kimi-k3",   // sent verbatim upstream
  "name": "Kimi K3 (Hawk)",
  "backend": "openai",                      // or "anthropic"
  "openaiApi": "openai-completions",        // openai backends only
  "reasoning": true,
  "input": ["text", "image"],
  "contextWindow": 1048576,
  "maxTokens": 131072,
  "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 0 }
}
```

### Gotchas

- **`enabledModels` and slashes.** Model ids can contain `/` (e.g. OpenRouter
  routes). pi matches `enabledModels` with minimatch, where `*` does **not**
  cross `/`. Use `hawk/**` so those ids appear in the picker.
- **Adaptive-thinking Anthropic models.** Some Anthropic models require
  `thinking.type.adaptive` + `output_config.effort` rather than the legacy
  `thinking.type.enabled` shape (which they reject). For those, set on the extra
  model:

  ```jsonc
  "reasoning": true,
  "compat": { "forceAdaptiveThinking": true }
  ```

  The provider forwards `compat` (and optional `thinkingLevelMap`) onto the
  pi-ai model. Without `compat`, requesting thinking fails with
  `"thinking.type.enabled" is not supported for this model`.
- **Change thinking level** at runtime with `Shift+Tab` (cycle) or `/thinking`;
  set the persistent default via `defaultThinkingLevel` in `settings.json`.
