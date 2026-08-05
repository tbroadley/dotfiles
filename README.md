# Dotfiles

Personal dotfiles for dev container setup.

## Setup

Clone and run the install script:

```bash
git clone https://github.com/tbroadley/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

## Claude Code Authentication in Dev Containers

Claude Code stores its API key in the macOS Keychain (service "Claude Code"), which isn't accessible from containers. The `devc` function reads the key from the keychain and forwards it as `ANTHROPIC_API_KEY` to containers automatically.

### Setup

1. Log in to Claude Code on your Mac: `claude /login`
2. Use dev containers as normal — `devc` handles forwarding.

## Codex Configuration in Dev Containers

The `install.sh` script configures Codex inside dev containers:

- Installs a default config from `codex/config.toml` to `~/.codex/config.toml` (no approval prompts, workspace-write sandbox, network enabled).
- Syncs Claude skills from `claude/skills` into `~/.codex/skills` via symlinks.

Codex does not support Claude Code plugins. If you want plugin-like integrations, add MCP servers to `codex/config.toml` instead.
On the host, running `install.sh` will also link `~/.codex/config.toml` to `~/dotfiles/codex/config.toml`.

### Codex Auth Forwarding

Codex can store auth in `~/.codex/auth.json` when `cli_auth_credentials_store = "file"` is set. The `devc` functions forward that file into containers if it exists on the host, so Codex works without re-auth prompts inside dev containers. See the Codex authentication docs for details about file-based storage and copying `auth.json` to headless environments.

## Pi Configuration in Dev Containers

The `install.sh` script also configures pi inside dev containers:

- Installs `@mariozechner/pi-coding-agent` globally.
- Symlinks `pi/agent/settings.json` to `~/.pi/agent/settings.json`.
- Reuses Claude skills by pointing pi at `~/.claude/skills` in the default settings.

Pi can authenticate with forwarded API keys like `ANTHROPIC_API_KEY`, or you can run `pi` and use `/login` inside the container.

### Host Pi Settings Symlink

If you want the same pi settings on your host machine, run this once:

```bash
mkdir -p ~/.pi/agent
ln -sfn ~/dotfiles/pi/agent/settings.json ~/.pi/agent/settings.json
```

### Host Skills Symlink

If you want Codex to use the Claude skills on your host machine, run this once:

```bash
mkdir -p ~/.codex/skills
for d in ~/dotfiles/claude/skills/*; do
  [ -d "$d" ] || continue
  ln -sfn "$d" "$HOME/.codex/skills/$(basename "$d")"
done
```

## Claude Skills Setup

The skill loader treats Markdown files inside `claude/skills/` as skills, so setup notes live here in the repo README instead of alongside the skills.

### Quick reference

| Skill | Setup required | Env var(s) |
|-------|---------------|------------|
| alfred-clipboard | None | - |
| learn | None | - |
| linear | API key | `LINEAR_API_KEY` |
| datadog | API + app keys | `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` |
| airtable | Personal access token | `AIRTABLE_TOKEN` |
| bitwarden | CLI + vault login | `BW_SESSION` (set by `bwunlock`) |
| gws-calendar / gws-gmail / gws-drive | gws CLI + auth | `GOOGLE_WORKSPACE_CLI_CLIENT_ID`, `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` |
| read-inspect-eval | Python package | `uv pip install inspect-ai` |
| download-inspect-eval | AWS CLI + SSO | default profile (downloads); `prd` profile for listing |
| hawk-monitoring / hawk-view-results | hawk CLI | `uv pip install hawk-cli` |

### Common setup

**No secrets go on disk.** They live as custom fields on a single Bitwarden item
and are pulled into the environment on demand by `secrets.zsh`, which `.zshrc`
sources. Add a new credential by adding a field to that item — nothing here
needs to change.

Unlock once per shell, then run whatever you need:

```bash
bwunlock          # prompts for the master password; exports BW_SESSION
```

Commands listed in `METR_SECRET_COMMANDS` (see `secrets.zsh`) load credentials
automatically on first use, so `bwunlock` is usually the only manual step. To
load them eagerly, or to refresh after rotating a key:

```bash
secrets-load      # no-op if already loaded
secrets-load -f   # force a re-fetch
```

`secrets-load` is idempotent for the life of a shell, so **a key rotated
elsewhere will not appear in shells that already loaded the old value** until
you run `secrets-load -f` or open a new terminal.

Non-secret machine config — `DD_SITE`, OAuth client ids, the vault item name —
belongs in `~/.zshrc.local`, which is deliberately untracked because this repo
is public. Extend the auto-load list there too:

```bash
METR_SECRET_COMMANDS+=(my-tool)
```

### Service-specific notes

- `linear`: create a personal API key at <https://linear.app/settings/account/security>
- `datadog`: create API and application keys in Datadog org settings
- `airtable`: create a token at <https://airtable.com/create/tokens> with `data.records:read` and `schema.bases:read`
- `bitwarden`: install `bitwarden-cli` and run `bw login` once; thereafter `bwunlock` handles unlocking per shell. Keep the master password in the login keychain and that unlock is a fingerprint rather than a typed password — `secrets.zsh` names the entry it looks for and how to create it. Without that entry, or without Touch ID for `sudo`, `bwunlock` prompts for the master password as before. `BW_SESSION` is never written to disk — it lives only in the shell that ran `bwunlock`.
- Google Workspace skills: install `@googleworkspace/cli`, create a desktop OAuth client in the `metr-pub` project, export the client ID/secret, then run `gws auth login`
- `read-inspect-eval`: `uv pip install inspect-ai`
- `download-inspect-eval`: requires an authenticated AWS SSO session (run `aws sso login` first). The skill handles the specific access point and bucket.
- `hawk-monitoring` / `hawk-view-results`: `uv pip install hawk-cli`

### Smoke tests

```bash
curl -s -X POST "https://api.linear.app/graphql" \
  -H "Authorization: $(printenv LINEAR_API_KEY)" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { name } }"}' | jq '.data.viewer.name'

curl -s "https://api.$(printenv DD_SITE)/api/v1/validate" \
  -H "DD-API-KEY: $(printenv DD_API_KEY)" \
  -H "DD-APPLICATION-KEY: $(printenv DD_APP_KEY)"

curl -s "https://api.airtable.com/v0/meta/bases" \
  -H "Authorization: Bearer $(printenv AIRTABLE_TOKEN)" | jq '.bases[].name'

gws calendar +agenda --today
gws gmail +triage --max 3
gws drive files list --params '{"pageSize": 5}'

bw status --session "$(printenv BW_SESSION)" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"

sqlite3 ~/Library/Application\ Support/Alfred/Databases/clipboard.alfdb \
  "SELECT substr(item, 1, 50) FROM clipboard ORDER BY ts DESC LIMIT 5;"
```

## URL Listener Service

The `url-listener` is an HTTP server (port 7077) that enables dev containers to interact with the host machine:

- **Open URLs** in the host's default browser
- **Open files/directories** in Cursor attached to the container
- **Open files** in Preview on the host
- **Clipboard forwarding** (pbcopy/pbpaste) between container and host
- **Wispr dictionary** additions from within containers

### Setup

The service is managed by launchd and starts automatically on login:

```bash
# Install the LaunchAgent (one-time setup)
cp ~/dotfiles/launchd/com.thomas.url-listener.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.thomas.url-listener.plist
```

### Managing the service

```bash
# Check status
launchctl list | grep url-listener

# View logs
tail -f ~/Library/Logs/url-listener.log

# Restart the service
launchctl kickstart -k gui/$(id -u)/com.thomas.url-listener

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.thomas.url-listener.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.thomas.url-listener.plist
```

### Health check

```bash
curl http://localhost:7077/health
# Returns "OK" if running
```

## Credential Broker

Agents on a remote box occasionally need a credential — a Datadog token, say.
Putting one in their environment does not work: everything an agent reads and
writes lands in a durable session transcript, so one `env` disclosure is
permanent. The broker gives them the *effect* of a credential instead.

Two halves. On the box, `with-secret` runs one command with one field in the
child's environment:

```bash
with-secret DD_PAT -- pup metrics query 'avg:system.cpu.user{*}'
```

On the laptop, `credential-broker` authenticates the request, checks the command
against an allowlist, asks me to approve it, unlocks the vault using the master
password from the login keychain, reads exactly one field out of Bitwarden, and
returns it. The value is never printed, never written to disk,
and is scrubbed out of the command's stdout and stderr on the way back. There is
deliberately no way to ask for a value without a command attached.

The allowlist lives on the laptop, not the box, so an agent cannot edit its way
around it. Shell wrappers (`sh`, `env`, `xargs`, ...) are refused as the command,
and `curl` is allowed only for a specific API host with a closed set of flags.

### Setup — laptop

The master password must be in the login keychain under the service `bw-master`
(`CREDENTIAL_BROKER_KEYCHAIN_ITEM` to use another), which is a prerequisite:

```bash
security add-generic-password -U -s bw-master -a "$USER" -w
```

The broker reads it only *after* an approval — the vault is never unlocked
speculatively — and falls back to asking at the keyboard if the item is missing.
That is not a weakening of the gate: the gate is the per-request approval alert,
and anything running as me could read the same keychain item directly. The
unlocked session lives in the broker's memory, never on disk, and is dropped
after `CREDENTIAL_BROKER_SESSION_TTL` seconds of inactivity.

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(32))'   # the shared token

cat > ~/.config/credential-broker.env <<'CONF'
CREDENTIAL_BROKER_TOKEN=<the token you just generated>
DD_SITE=<datadog site>
CONF
chmod 600 ~/.config/credential-broker.env

~/dotfiles/bin/credential-broker --check             # config, bind address, allowlist
~/dotfiles/bin/credential-broker --test-field DD_PAT # is that field really there?

cp ~/dotfiles/launchd/com.thomas.credential-broker.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.thomas.credential-broker.plist
tail -f ~/Library/Logs/credential-broker.log
```

It binds this machine's tailnet address, never `0.0.0.0`, and refuses to start
if it cannot work out what that is.

`DD_SITE` is what enables the `curl` rule for the Datadog API host; without it,
`pup` only, and `--check` says so. Put it in the config file rather than the
plist: launchd does not inherit a login shell's environment, and the plist is
in this public repo while the config file is not.

`--test-field` reads one field and reports its length, never its value, which is
the quick way to confirm the vault item actually has the field before an agent
finds out the hard way. The name the box asks for is the variable the command
needs (`pup` wants `DD_PAT`); if the vault calls that field something else, map
it rather than renaming either:

```
CREDENTIAL_BROKER_VAULT_FIELD_DD_PAT=<whatever the field is called in the item>
```

### Setup — the box

```bash
cat > ~/.config/credential-broker.env <<'CONF'
CREDENTIAL_BROKER_HOST=<laptop's tailnet name or IP>
CREDENTIAL_BROKER_TOKEN=<the same token>
CONF
chmod 600 ~/.config/credential-broker.env
```

`install.sh` symlinks `with-secret` into `~/.pi/agent/bin`, which pi puts on the
agent PATH — agents do not source `.zshrc`, so that is how they see it.

The bearer token only buys the ability to *raise a prompt*; losing it costs
prompt spam, not credentials. The box holds nothing else: no vault, no Bitwarden
CLI, no session key.

### Using it

Where a tool wants the credential in an argument rather than the environment,
write `{{FIELD}}` and it is substituted just before exec — nothing else expands
it, since no shell is involved:

```bash
with-secret DD_PAT --reason 'checking the runner error rate' -- \
  curl -sS -H 'Authorization: Bearer {{DD_PAT}}' "https://api.$DD_SITE/api/v2/current_user"
```

Exit codes distinguish the failures that need a human: 2 the laptop is
unreachable, 3 refused by the allowlist or denied, 4 nobody answered. Every
request, approved or not, is appended to
`~/Library/Logs/credential-broker-audit.jsonl` on the laptop.

### Limits

The allowlist constrains the *name* of the command, and the name resolves on the
box, so it bounds mistakes and makes the prompt meaningful — it is not a sandbox
against a host where someone has already planted their own `pup`. The value is
briefly in memory there too. The way out of both is proxy mode, where the laptop
makes the API call and the credential never crosses the network; worth building
for a credential dangerous enough to deserve it.

### Tests

```bash
./tests/with-secret.test.sh          # box half, against a fake broker
python3 tests/credential-broker.test.py   # allowlist, curl parsing, grants, audit
```
