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
| todoist | API token | `TODOIST_TOKEN` |
| linear | API key | `LINEAR_API_KEY` |
| datadog | API + app keys | `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` |
| airtable | Personal access token | `AIRTABLE_TOKEN` |
| bitwarden | CLI + vault login | `BW_SESSION` |
| gws-calendar / gws-gmail / gws-drive | gws CLI + auth | `GOOGLE_WORKSPACE_CLI_CLIENT_ID`, `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` |
| read-inspect-eval | Python package | `uv pip install inspect-ai` |
| download-inspect-eval | AWS CLI + profile | `AWS_PROFILE=production` |
| hawk-monitoring / hawk-view-results | hawk CLI | `uv pip install hawk-cli` |

### Common setup

Add secrets to `~/.zshrc.local`:

```bash
export TODOIST_TOKEN="..."
export LINEAR_API_KEY="..."
export DD_API_KEY="..."
export DD_APP_KEY="..."
export DD_SITE="us3.datadoghq.com"
export AIRTABLE_TOKEN="..."
export BW_SESSION="..."
export GOOGLE_WORKSPACE_CLI_CLIENT_ID="..."
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="..."
```

Then reload your shell:

```bash
source ~/.zshrc.local
```

### Service-specific notes

- `todoist`: create a token at <https://todoist.com/app/settings/integrations/developer>
- `linear`: create a personal API key at <https://linear.app/settings/account/security>
- `datadog`: create API and application keys in Datadog org settings
- `airtable`: create a token at <https://airtable.com/create/tokens> with `data.records:read` and `schema.bases:read`
- `bitwarden`: install `bitwarden-cli`, run `bw login`, then `bw unlock` and export `BW_SESSION`
- Google Workspace skills: install `@googleworkspace/cli`, create a desktop OAuth client in the `metr-pub` project, export the client ID/secret, then run `gws auth login`
- `read-inspect-eval`: `uv pip install inspect-ai`
- `download-inspect-eval`: verify access with `AWS_PROFILE=production aws s3 ls s3://production-metr-inspect-data/`
- `hawk-monitoring` / `hawk-view-results`: `uv pip install hawk-cli`

### Smoke tests

```bash
curl -s "https://api.todoist.com/rest/v2/projects" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" | jq '.[].name'

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
