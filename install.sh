#!/bin/bash
set -euo pipefail

# Devcontainer dotfiles setup script
# Runs inside the container when VS Code/Cursor opens a devcontainer
# All installations are user-local, no root access required

echo "Setting up devcontainer dotfiles..."

# Set USER if not set
USER="${USER:-$(whoami)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup inputrc for history search (user-local only)
if [ -f "$HOME/.inputrc" ] && grep -q "history-search-backward" "$HOME/.inputrc"; then
  echo "inputrc already configured"
else
  cat >> "$HOME/.inputrc" << 'EOF'
## arrow up
"\e[A":history-search-backward
## arrow down
"\e[B":history-search-forward
EOF
  echo "inputrc configured"
fi

# Setup gitconfig and gitignore
cp "$SCRIPT_DIR/gitconfig" "$HOME/.gitconfig"
cp "$SCRIPT_DIR/gitignore" "$HOME/.gitignore"
echo "gitconfig and gitignore installed"

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
echo "bashrc aliases configured"

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Install ripgrep to ~/.local/bin
if command -v rg >/dev/null 2>&1; then
  echo "ripgrep is already installed: $(rg --version | head -1)"
else
  echo "Installing ripgrep..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) RG_ARCH="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) RG_ARCH="aarch64-unknown-linux-gnu" ;;
    *) echo "Unsupported architecture for ripgrep: $ARCH"; exit 1 ;;
  esac

  RG_VERSION="14.1.1"
  wget -O /tmp/rg.tar.gz "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${RG_ARCH}.tar.gz"
  mkdir -p /tmp/rg
  tar -xzf /tmp/rg.tar.gz -C /tmp/rg --strip-components=1
  mv /tmp/rg/rg "$HOME/.local/bin/"
  rm -rf /tmp/rg.tar.gz /tmp/rg
  chmod +x "$HOME/.local/bin/rg"
  echo "ripgrep installation completed"
fi

# Install jq to ~/.local/bin
if command -v jq >/dev/null 2>&1; then
  echo "jq is already installed: $(jq --version)"
else
  echo "Installing jq..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) JQ_ARCH="amd64" ;;
    aarch64|arm64) JQ_ARCH="arm64" ;;
    *) echo "Unsupported architecture for jq: $ARCH"; exit 1 ;;
  esac

  JQ_VERSION="1.7.1"
  wget -O "$HOME/.local/bin/jq" "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${JQ_ARCH}"
  chmod +x "$HOME/.local/bin/jq"
  echo "jq installation completed"
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

# Install @openai/codex
if npm list -g @openai/codex >/dev/null 2>&1; then
  echo "@openai/codex is already installed globally"
else
  echo "Installing @openai/codex globally..."
  npm install -g @openai/codex
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

# Install shell-alias-suggestions
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
