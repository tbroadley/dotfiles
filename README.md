# Dotfiles

Personal dotfiles for dev container setup.

## Setup

Clone and run the install script:

```bash
git clone https://github.com/tbroadley/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

## Claude Code Authentication in Dev Containers

Claude Code uses OAuth tokens stored in the macOS Keychain, which aren't accessible from containers. To authenticate Claude Code in dev containers:

### 1. Generate a long-lived token

Run this on your Mac:

```bash
claude setup-token
```

This outputs an OAuth token valid for 1 year.

### 2. Add the token to your shell config

Add to your `~/.zshrc` (before sourcing the dotfiles):

```bash
export CLAUDE_CODE_OAUTH_TOKEN="<your-token-here>"
```

### 3. Use dev containers as normal

The `devc` function automatically forwards `CLAUDE_CODE_OAUTH_TOKEN` to containers. The `install.sh` script configures Claude Code to use the token.

### Refreshing the token

When the token expires (after ~1 year), run `claude setup-token` again and update your `~/.zshrc`.

## Codex Configuration in Dev Containers

The `install.sh` script configures Codex inside dev containers:

- Installs a default config from `codex/config.toml` to `~/.codex/config.toml` (no approval prompts, workspace-write sandbox, network enabled).
- Syncs Claude skills from `claude/skills` into `~/.codex/skills` via symlinks.

Codex does not support Claude Code plugins. If you want plugin-like integrations, add MCP servers to `codex/config.toml` instead.
On the host, running `install.sh` will also link `~/.codex/config.toml` to `~/dotfiles/codex/config.toml`.

### Codex Auth Forwarding

Codex can store auth in `~/.codex/auth.json` when `cli_auth_credentials_store = "file"` is set. The `devc` functions forward that file into containers if it exists on the host, so Codex works without re-auth prompts inside dev containers. See the Codex authentication docs for details about file-based storage and copying `auth.json` to headless environments.

### Host Skills Symlink

If you want Codex to use the Claude skills on your host machine, run this once:

```bash
mkdir -p ~/.codex/skills
for d in ~/dotfiles/claude/skills/*; do
  [ -d "$d" ] || continue
  ln -sfn "$d" "$HOME/.codex/skills/$(basename "$d")"
done
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
