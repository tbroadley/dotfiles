# Pirouette customizations

Notes on my setup for [pirouette](https://github.com/neevparikh/pirouette) — a
single-user runner for long-lived [pi](https://github.com/earendil-works/pi-coding-agent)
coding agents on an SSH-reachable host. This documents the additions I make on
top of a stock install; it is not a fork of pirouette's own docs.

I run my own fork, [`tbroadley/pirouette`](https://github.com/tbroadley/pirouette).

## Host shape

- **systemd-managed** service (`pirouette.service`) rather than the tmux
  launcher — a plain `sudo systemctl restart pirouette` restarts it, and logs
  go to the file `pru logs` tails.
- **Single-volume host**: `adopt = true` with a persistent root (e.g. `/data`)
  and `$HOME` left in place, so there is no `$HOME` migration.
- **Tailscale**: `tailscale serve` fronts the loopback-bound dashboard so it is
  reachable over the tailnet without an SSH tunnel. (Host/tailnet names are
  environment-specific and kept out of this repo.)

## pi configuration

The agent config lives in [`../pi`](../pi) and is deployed by `install.sh`; see
[`../pi/README.md`](../pi/README.md). The pieces most relevant on a pirouette
host:

- **hawk provider + model guardrail** — agents default to the `hawk` provider
  (`defaultProvider: hawk`, `enabledModels: ["hawk/**"]`), and
  `extensions/hawk-only.ts` reverts any non-hawk model selection.
- **Custom extensions** (via `settings.json` `packages`):
  [`pi-hawk-provider`](https://github.com/tbroadley/pi-hawk-provider) (fork),
  [`pi-btw`](https://github.com/tbroadley/pi-btw) (`/btw` side questions), and
  [`pi-manage-todo-list`](https://github.com/tbroadley/pi-manage-todo-list)
  (structured todo list).
- **Skill tokens for all agents** — `extensions/agent-tokens.ts` reads
  `~/.pi/agent/agent-tokens.env` (gitignored) and injects each token into the
  server environment, so every agent (current and future) can use token-based
  skills without per-agent setup. See
  [Skill tokens](../pi/README.md#skill-tokens).
- **CLI tools on the agent PATH** — `fd` and `rg` binaries dropped in
  `~/.pi/agent/bin/` (pi prepends that dir to each agent's PATH).

## Adding a skill token for all agents

1. Add the `KEY=VALUE` line to `~/.pi/agent/agent-tokens.env` on the host
   (`chmod 600`; never commit it).
2. `sudo systemctl restart pirouette`.
3. Confirm the log line
   `[agent-tokens] injected into agent environment: ...` includes the new key.

Only single, static, env-var tokens belong there — not interactive/OAuth
credentials (bitwarden, gws-*, hawk/AWS/gh have their own login flows).
