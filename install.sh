#!/bin/bash
set -euo pipefail

# Devcontainer dotfiles setup script
# Runs inside the container when VS Code/Cursor opens a devcontainer

echo "Setting up devcontainer dotfiles..."

# Set USER if not set
USER="${USER:-$(whoami)}"

# Helper to run commands as root (use sudo if available, otherwise run directly)
run_root() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

# Install packages
run_root apt-get update && run_root apt-get install -y vim ripgrep unzip

# Setup inputrc for history search
setup_inputrc() {
  local inputrc_file="$1"
  local owner="$2"

  if [ -f "$inputrc_file" ] && grep -q "history-search-backward" "$inputrc_file"; then
    return 0
  fi

  run_root tee -a "$inputrc_file" > /dev/null << 'EOF'
## arrow up
"\e[A":history-search-backward
## arrow down
"\e[B":history-search-forward
EOF

  if [ -n "$owner" ]; then
    run_root chown "$owner:$owner" "$inputrc_file"
  fi
}

setup_inputrc "/etc/inputrc" ""
setup_inputrc "$HOME/.inputrc" "$USER"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup gitconfig and gitignore
cp "$SCRIPT_DIR/gitconfig" "$HOME/.gitconfig"
cp "$SCRIPT_DIR/gitignore" "$HOME/.gitignore"

# Setup bashrc additions
add_to_bashrc() {
  local pattern="$1"
  local line="$2"
  if ! grep -qF "$pattern" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
  fi
}

add_to_bashrc "alias g=git" "alias g=git"
add_to_bashrc "alias v=vim" "alias v=vim"
add_to_bashrc "alias c=" 'alias c="unset ANTHROPIC_BASE_URL && claude"'
add_to_bashrc "alias d=dvc" "alias d=dvc"
add_to_bashrc "alias r=ruff" "alias r=ruff"
add_to_bashrc "alias b=basedpyright" "alias b=basedpyright"
add_to_bashrc "alias pt=pytest" "alias pt=pytest"
add_to_bashrc 'alias psa=' 'alias psa="dvc push && git push"'
add_to_bashrc 'alias pla=' 'alias pla="git pull && dvc pull"'
add_to_bashrc "export EDITOR=vim" "export EDITOR=vim"
add_to_bashrc "source /etc/bash_completion.d/git-prompt" "source /etc/bash_completion.d/git-prompt"
add_to_bashrc "source /usr/share/bash-completion/completions/git" "source /usr/share/bash-completion/completions/git"
add_to_bashrc "__git_complete g __git_main" "__git_complete g __git_main"
add_to_bashrc 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi' 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi'
add_to_bashrc 'export PATH="$HOME/.local/bin:$PATH"' 'export PATH="$HOME/.local/bin:$PATH"'

# Uninstall globally installed node if it exists and save global packages
if dpkg -l | grep -q "^ii.*nodejs"; then
  echo "Found nodejs installed via apt, saving list of global packages..."
  if command -v npm >/dev/null 2>&1; then
    npm list -g --depth=0 --json > /tmp/global_npm_packages.json 2>/dev/null || echo "{}" > /tmp/global_npm_packages.json
  fi

  echo "Uninstalling nodejs and npm..."
  run_root apt-get remove -y nodejs npm
  run_root apt-get autoremove -y
  run_root rm -f /etc/apt/sources.list.d/nodesource.list
  run_root rm -f /etc/apt/keyrings/nodesource.gpg
  echo "Global nodejs has been uninstalled"
fi

# Install nvm and Node.js
if [ ! -d "$HOME/.nvm" ]; then
  echo "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! nvm current >/dev/null 2>&1 || [ "$(nvm current)" = "none" ] || [ "$(nvm current)" = "system" ]; then
  echo "Installing LTS version of Node.js via nvm..."
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
else
  echo "Node.js is already installed via nvm: $(nvm current) ($(node --version))"
fi

# Reinstall global packages from the saved list
if [ -f /tmp/global_npm_packages.json ]; then
  echo "Reinstalling global npm packages..."
  PACKAGES=$(cat /tmp/global_npm_packages.json | grep -o '"[^"]*":' | sed 's/"//g' | sed 's/://g' | grep -v "^npm$" | grep -v "^lib$" | grep -v "^dependencies$")
  for pkg in $PACKAGES; do
    if [ -n "$pkg" ]; then
      echo "Installing $pkg..."
      npm install -g "$pkg" || echo "Failed to install $pkg, skipping..."
    fi
  done
fi

# Install @openai/codex
if npm list -g @openai/codex >/dev/null 2>&1; then
  echo "@openai/codex is already installed globally"
else
  echo "Installing @openai/codex globally..."
  npm install -g @openai/codex
fi

# Install jj
if command -v jj >/dev/null 2>&1; then
  echo "jj is already installed: $(jj --version)"
else
  echo "Installing jj..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) JJ_ARCH="x86_64" ;;
    aarch64|arm64) JJ_ARCH="aarch64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  JJ_VERSION="0.34.0"
  wget -O /tmp/jj.tar.gz "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-${JJ_ARCH}-unknown-linux-musl.tar.gz"
  mkdir -p /tmp/jj
  tar -xzf /tmp/jj.tar.gz -C /tmp/jj
  run_root mv /tmp/jj/jj /usr/local/bin/
  rm -rf /tmp/jj.tar.gz /tmp/jj
  run_root chmod +x /usr/local/bin/jj
  echo "jj installation completed"
fi

# Install jjui
if command -v jjui >/dev/null 2>&1; then
  echo "jjui is already installed: $(jjui --version)"
else
  echo "Installing jjui..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) JJUI_ARCH="amd64" ;;
    aarch64|arm64) JJUI_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  JJUI_VERSION="0.9.5"
  wget -O /tmp/jjui.zip "https://github.com/idursun/jjui/releases/download/v${JJUI_VERSION}/jjui-${JJUI_VERSION}-linux-${JJUI_ARCH}.zip"
  unzip -q /tmp/jjui.zip -d /tmp/jjui
  run_root mv "/tmp/jjui/jjui-${JJUI_VERSION}-linux-${JJUI_ARCH}" /usr/local/bin/jjui
  rm -rf /tmp/jjui.zip /tmp/jjui
  run_root chmod +x /usr/local/bin/jjui
  echo "jjui installation completed"
fi

# Install Claude Code
if command -v claude >/dev/null 2>&1; then
  echo "Claude Code is already installed: $(claude --version)"
else
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "Claude Code installation completed"
fi

# Configure Claude Code settings
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_DIR/settings.json"
mkdir -p "$CLAUDE_SETTINGS_DIR"

if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
  if grep -q "cleanupPeriodDays" "$CLAUDE_SETTINGS_FILE"; then
    echo "cleanupPeriodDays is already configured in Claude Code settings"
  else
    if command -v jq >/dev/null 2>&1; then
      jq '. + {"cleanupPeriodDays": 999999}' "$CLAUDE_SETTINGS_FILE" > "$CLAUDE_SETTINGS_FILE.tmp" && mv "$CLAUDE_SETTINGS_FILE.tmp" "$CLAUDE_SETTINGS_FILE"
    else
      sed -i 's/}$/,"cleanupPeriodDays": 999999}/' "$CLAUDE_SETTINGS_FILE"
    fi
    echo "Added cleanupPeriodDays to Claude Code settings"
  fi
else
  echo '{"cleanupPeriodDays": 999999}' > "$CLAUDE_SETTINGS_FILE"
  echo "Created Claude Code settings with cleanupPeriodDays"
fi

# Configure jj
jj config set --user editor "vim"
jj config set --user user.name "Thomas Broadley"
jj config set --user user.email "thomas@metr.org"

# Install shell-alias-suggestions
export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1; then
  echo "Installing/upgrading shell-alias-suggestions..."
  uv tool install --upgrade git+https://github.com/tbroadley/shell-alias-suggestions.git
  if ! grep -q "alias-suggest" "$HOME/.bashrc" 2>/dev/null; then
    echo "Installing shell-alias-suggestions hooks..."
    alias-suggest install --bash
    echo "shell-alias-suggestions installation completed"
  else
    echo "shell-alias-suggestions hooks already installed"
  fi
else
  echo "uv not found, skipping shell-alias-suggestions installation"
fi

echo "Devcontainer configuration completed"
