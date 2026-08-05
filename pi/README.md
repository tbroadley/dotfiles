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
  - `auto-mode.ts` — a port of Claude Code's auto mode: run without permission
    prompts, with a classifier LLM gating each tool call (see
    [Auto mode](#auto-mode) below).

Tests for the extensions live in [`pi/tests`](tests): `cd pi/tests && npm
install && npx vitest run`.

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

## Auto mode

`extensions/auto-mode.ts` ports [Claude Code's auto
mode](https://code.claude.com/docs/en/auto-mode-config) to pi: instead of
prompting for permission, every `tool_call` is judged by a classifier LLM, which
blocks irreversible, destructive or externally-aimed actions and lets routine
work through. It is meant for unattended agents (a pirouette host), where a
permission prompt has nobody to answer it.

- **Classifier model** follows the agent's family — Anthropic agent →
  `claude-sonnet-5`, OpenAI agent → `gpt-5.6-luna`, anything else is a hard
  error at `before_agent_start`. The agent keeps its own model.
- **Off by default.** Turn on per session with `--auto-mode` or `/auto-mode on`;
  other subcommands are `off`, `status`, `config`, `defaults`.
- **On by default** via `~/.pi/agent/auto-mode.json`: `{"enabled": true}` for
  every pi session on the host, or `{"enabled": "pirouette"}` for only the
  agents the pirouette server starts (detected from `PIROUETTE_*` env vars).
- **The gate runs in every mode the agent uses tools** (interactive, RPC and
  `-p` print). In non-interactive modes there is no status line or
  notification, but blocked tool calls still come back with the reason.

### Configuration

`~/.pi/agent/auto-mode.json`, plus `<project>/.pi/auto-mode.json` for trusted
projects. All keys optional; include the literal `"$defaults"` in a rule list to
keep the built-in rules and add to them, or omit it to take full ownership.

```jsonc
{
  "environment": ["$defaults", "Source control: github.com/acme and repos under it"],
  "allow":       ["$defaults", "Writing to s3://acme-scratch/ is allowed (ephemeral)"],
  "soft_deny":   ["$defaults", "Never run migrations outside the migrations CLI"],
  "hard_deny":   ["$defaults", "Never send repo contents to third-party APIs"],
  "trustedPaths": ["/data/scratch"],  // extra roots that count as "this machine"
  "classifyReadOnlyTools": false,     // also classify read/ls/grep/find (default: false)
  "readOnlyBashFastPath": true,       // skip the classifier for provably read-only shell
  "failClosed": true,                 // block mutating tools if the classifier errors
  "enabled": "pirouette"
}
```

`/auto-mode config` prints the merged config along with the resolved trusted
roots, so the boundary is inspectable from inside a session.

### Design notes

The first version blocked far too much — in an audit of a few days of session
logs, roughly 45 of ~50 blocks were false positives, and two agents never
recovered. The two dominant causes and their fixes:

- **Trust was scoped to `cwd`.** A sibling worktree of the *same repo on the
  same disk* read as "external", as did `/tmp`. The trust boundary is now the
  machine and the user's own repos and dev boxes: `trustedRoots()` computes
  concrete paths (cwd, the parent of `git rev-parse --git-common-dir` so every
  worktree of the repo counts, `$TMPDIR`, `/tmp`,
  `$PIROUETTE_DATA_DIR/{worktrees,repos}`, plus `trustedPaths`) and injects them
  into the prompt. Multi-worktree, multi-repo work is the normal mode of
  operation, not a red flag.
- **Authorization was thrown away.** Only the single latest user message was
  passed, so backward-referring approvals ("yes, go ahead with both of those")
  lost their referent and read as vague. `recentConversation()` now passes the
  last 8 user *and* assistant turns, with auto mode's own block notices filtered
  out so they can't feed back in as intent.

Also: the prompt is allow-by-default with an explicit "these are NOT reasons to
block" list (path outside cwd, short/absent/apologetic last message,
pronoun-shaped authorization, risky-sounding *words* without a risky effect,
plain uncertainty); the verdict JSON puts `reason` before `decision` so the
model reasons before it labels; the hard deny on reconfiguring auto mode is
narrowed to *weakening it to get an action past it*, so the extension stays
maintainable by an agent; an unparseable verdict is retried once before
blocking; and `isReadOnlyBash()` skips the classifier entirely for shell whose
every segment is provably read-only (quote-aware, so a `|` inside a grep regex
isn't a pipe), which removes both the latency and a false-positive roll on every
`git log`.

Not loosened: third-party exfiltration, publishing secrets, force pushes and
history rewriting, production writes, `curl | bash` from unknown sources, DB
drops, and fail-closed behaviour on classifier errors.

### Deploying to a pirouette host

The pirouette host does not run `install.sh`, and pi auto-loads every `.ts` in
`~/.pi/agent/extensions/`, so deploy by copying the file and restarting the
service (extensions load with the host process, so a restart is what picks up a
new version for both running and future agents):

```sh
scp pi/agent/extensions/auto-mode.ts <host>:~/.pi/agent/extensions/auto-mode.ts
ssh <host> 'sudo systemctl restart pirouette'
```

## Skill tokens

`settings.json` loads `~/.claude/skills` (and `~/.codex/skills`) into pi, so
agents can use those skills. Several skills authenticate with a single static
token read from an env var (e.g. `LINEAR_API_KEY`, `AIRTABLE_TOKEN`,
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
