# pi configuration

Config for [pi](https://github.com/earendil-works/pi-coding-agent) lives in
`pi/agent/` and is deployed by `install.sh`:

- `settings.json` — merged onto any existing local settings (dotfiles keys win,
  local-only keys like `defaultModel` preserved).
- `models.json` — copied to `~/.pi/agent/models.json` **only when no local file
  exists**. It is never overwritten or merged, so a local `models.json` may hold
  additional (e.g. private/internal) model entries that are not committed here.
- `AGENTS.md` — symlinked.
- `extensions/*.ts` — symlinked into `~/.pi/agent/extensions/` (extension files
  that exist only in the target dir and are not tracked here are left untouched):
  - `hawk-only.ts` — restricts model selection to the `hawk` provider.
  - `agent-tokens.ts` — injects static skill API tokens into every agent's
    environment (see [Skill tokens](#skill-tokens) below).
  - `auto-mode.ts` — a port of [Claude Code's auto
    mode](https://code.claude.com/docs/en/auto-mode-config). Off by default;
    enable with `--auto-mode` or `/auto-mode on`. It runs tool calls without
    permission prompts but routes each one through a *safety classifier* that
    blocks anything irreversible, destructive, or aimed outside your environment
    (force pushes, `rm -rf` outside the workspace, exfiltration, prod deploys,
    …) while letting routine work through. The classifier runs on
    `claude-sonnet-5` for Anthropic agents and `gpt-5.6-luna` for OpenAI agents;
    any other agent family raises a hard error that stops the agent. Trusted
    infrastructure and `allow`/`soft_deny`/`hard_deny` rules (with `"$defaults"`
    splicing) can be set in `~/.pi/agent/auto-mode.json` or a trusted project's
    `.pi/auto-mode.json`; inspect them with `/auto-mode config` and `/auto-mode
    defaults`. To turn it on by default (instead of per-session with
    `--auto-mode`), set `"enabled"` in that JSON: `true` enables it for every pi
    session on the host, `"pirouette"` enables it only for agents launched by
    the pirouette server (detected via its `PIROUETTE_*` env). The gate runs in
    every mode the agent uses tools (interactive,
    RPC, and `-p` print); in non-interactive modes there's no status line or
    notifications, but blocked tool calls still come back with the reason.

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

## Skill tokens

`settings.json` loads `~/.claude/skills` (and `~/.codex/skills`) into pi, so
agents can use those skills. Several skills authenticate with a single static
token read from an env var (e.g. `TODOIST_TOKEN`, `AIRTABLE_TOKEN`,
`LINEAR_API_KEY`, `DD_API_KEY`). `extensions/agent-tokens.ts` makes those tokens
available to every agent without per-agent setup: at load it reads
`~/.pi/agent/agent-tokens.env` and sets each `KEY=VALUE` in the process
environment (only if unset). Agents run in-process, and their bash tool inherits
the process env, so any shell/`curl` they run sees the tokens. The extension
registers nothing (no tools/commands/prompts), so it is silent.

Setup:

```sh
cp pi/agent/agent-tokens.env.example ~/.pi/agent/agent-tokens.env
$EDITOR ~/.pi/agent/agent-tokens.env      # fill in real values
chmod 600 ~/.pi/agent/agent-tokens.env
# restart the pi host so the extension reloads (pirouette systemd host):
#   sudo systemctl restart pirouette
```

`agent-tokens.env` holds secrets and is **gitignored** — only the
`.env.example` (key names, no values) is committed. See
[`agent-tokens.env.example`](agent/agent-tokens.env.example) for the managed
keys.

Only put single, static, env-var tokens here. Skills that use interactive
logins or refreshing credentials — bitwarden (`bw unlock`), gws-* (Google
OAuth), and anything on hawk / AWS SSO / `gh` — are handled by their own
login flows, not this file.
