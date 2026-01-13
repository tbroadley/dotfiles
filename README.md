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
