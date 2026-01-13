#!/bin/bash
set -euo pipefail

# Devcontainer dotfiles setup script
# Runs inside the container when VS Code/Cursor opens a devcontainer
# All installations are user-local, no root access required

echo "Setting up devcontainer dotfiles..."

# Checksum verification function
verify_checksum() {
  local file="$1"
  local expected_checksum="$2"
  local actual_checksum

  actual_checksum=$(sha256sum "$file" | awk '{print $1}')
  if [ "$actual_checksum" != "$expected_checksum" ]; then
    echo "ERROR: Checksum verification failed for $file"
    echo "  Expected: $expected_checksum"
    echo "  Actual:   $actual_checksum"
    rm -f "$file"
    return 1
  fi
  echo "Checksum verified for $file"
  return 0
}

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

# Setup shell rc additions (works with both bash and zsh)
add_to_rc() {
  local pattern="$1"
  local line="$2"
  local bash_only="${3:-false}"
  local zsh_only="${4:-false}"

  if [ "$bash_only" = "true" ]; then
    if [ -f "$HOME/.bashrc" ] && ! grep -qF "$pattern" "$HOME/.bashrc" 2>/dev/null; then
      echo "$line" >> "$HOME/.bashrc"
    fi
  elif [ "$zsh_only" = "true" ]; then
    if [ -f "$HOME/.zshrc" ] && ! grep -qF "$pattern" "$HOME/.zshrc" 2>/dev/null; then
      echo "$line" >> "$HOME/.zshrc"
    fi
  else
    # Add to both if they exist
    if [ -f "$HOME/.bashrc" ] && ! grep -qF "$pattern" "$HOME/.bashrc" 2>/dev/null; then
      echo "$line" >> "$HOME/.bashrc"
    fi
    if [ -f "$HOME/.zshrc" ] && ! grep -qF "$pattern" "$HOME/.zshrc" 2>/dev/null; then
      echo "$line" >> "$HOME/.zshrc"
    fi
  fi
}

# Aliases (work in both shells)
add_to_rc "alias g=git" "alias g=git"
add_to_rc "alias v=vim" "alias v=vim"
add_to_rc "alias c=" 'alias c="unset ANTHROPIC_BASE_URL && claude"'
add_to_rc "alias d=dvc" "alias d=dvc"
add_to_rc "alias r=ruff" "alias r=ruff"
add_to_rc "alias b=basedpyright" "alias b=basedpyright"
add_to_rc "alias pt=pytest" "alias pt=pytest"
add_to_rc 'alias psa=' 'alias psa="dvc push && git push"'
add_to_rc 'alias pla=' 'alias pla="git pull && dvc pull"'
add_to_rc "export EDITOR=vim" "export EDITOR=vim"
add_to_rc 'export PATH="$HOME/.local/bin:$PATH"' 'export PATH="$HOME/.local/bin:$PATH"'
add_to_rc 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi' 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi'

# Bash-specific completions
add_to_rc "source /etc/bash_completion.d/git-prompt" "source /etc/bash_completion.d/git-prompt 2>/dev/null" true false
add_to_rc "source /usr/share/bash-completion/completions/git" "source /usr/share/bash-completion/completions/git 2>/dev/null" true false
add_to_rc "__git_complete g __git_main" "__git_complete g __git_main 2>/dev/null" true false

# Zsh-specific setup
add_to_rc "autoload -Uz compinit && compinit" "autoload -Uz compinit && compinit" false true
add_to_rc "autoload -Uz vcs_info" "autoload -Uz vcs_info" false true

echo "shell rc configured"

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Install ripgrep to ~/.local/bin (Linux only, macOS uses brew)
if [ "$(uname -s)" = "Linux" ]; then
  if command -v rg >/dev/null 2>&1; then
    echo "ripgrep is already installed: $(rg --version | head -1)"
  else
    echo "Installing ripgrep..."
    ARCH=$(uname -m)
    case $ARCH in
      x86_64)
        RG_ARCH="x86_64-unknown-linux-musl"
        RG_CHECKSUM="4cf9f2741e6c465ffdb7c26f38056a59e2a2544b51f7cc128ef28337eeae4d8e"
        ;;
      aarch64|arm64)
        RG_ARCH="aarch64-unknown-linux-gnu"
        RG_CHECKSUM="c827481c4ff4ea10c9dc7a4022c8de5db34a5737cb74484d62eb94a95841ab2f"
        ;;
      *) echo "Unsupported architecture for ripgrep: $ARCH"; exit 1 ;;
    esac

    RG_VERSION="14.1.1"
    wget -O /tmp/rg.tar.gz "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${RG_ARCH}.tar.gz"
    verify_checksum /tmp/rg.tar.gz "$RG_CHECKSUM"
    mkdir -p /tmp/rg
    tar -xzf /tmp/rg.tar.gz -C /tmp/rg --strip-components=1
    mv /tmp/rg/rg "$HOME/.local/bin/"
    rm -rf /tmp/rg.tar.gz /tmp/rg
    chmod +x "$HOME/.local/bin/rg"
    echo "ripgrep installation completed"
  fi
fi

# Install jq to ~/.local/bin (Linux only, macOS uses brew)
if [ "$(uname -s)" = "Linux" ]; then
  if command -v jq >/dev/null 2>&1; then
    echo "jq is already installed: $(jq --version)"
  else
    echo "Installing jq..."
    ARCH=$(uname -m)
    case $ARCH in
      x86_64)
        JQ_ARCH="amd64"
        JQ_CHECKSUM="5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5"
        ;;
      aarch64|arm64)
        JQ_ARCH="arm64"
        JQ_CHECKSUM="4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5"
        ;;
      *) echo "Unsupported architecture for jq: $ARCH"; exit 1 ;;
    esac

    JQ_VERSION="1.7.1"
    wget -O /tmp/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${JQ_ARCH}"
    verify_checksum /tmp/jq "$JQ_CHECKSUM"
    mv /tmp/jq "$HOME/.local/bin/jq"
    chmod +x "$HOME/.local/bin/jq"
    echo "jq installation completed"
  fi
fi

# Install nvm and Node.js
if [ ! -d "$HOME/.nvm" ]; then
  echo "Installing nvm..."
  NVM_VERSION="0.40.1"
  NVM_CHECKSUM="abdb525ee9f5b48b34d8ed9fc67c6013fb0f659712e401ecd88ab989b3af8f53"
  curl -fsSL -o /tmp/nvm-install.sh "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
  verify_checksum /tmp/nvm-install.sh "$NVM_CHECKSUM"
  bash /tmp/nvm-install.sh
  rm -f /tmp/nvm-install.sh
fi

export NVM_DIR="$HOME/.nvm"
# nvm scripts have unbound variables, so temporarily disable -u
set +u
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! nvm current >/dev/null 2>&1 || [ "$(nvm current)" = "none" ] || [ "$(nvm current)" = "system" ]; then
  echo "Installing LTS version of Node.js via nvm..."
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
else
  echo "Node.js is already installed via nvm: $(nvm current) ($(node --version))"
fi
set -u

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
  # Note: Update this checksum when Claude Code releases new versions
  # Verify at: curl -fsSL https://claude.ai/install.sh | sha256sum
  CLAUDE_INSTALL_CHECKSUM="363382bed8849f78692bd2f15167a1020e1f23e7da1476ab8808903b6bebae05"
  curl -fsSL -o /tmp/claude-install.sh https://claude.ai/install.sh
  verify_checksum /tmp/claude-install.sh "$CLAUDE_INSTALL_CHECKSUM"
  bash /tmp/claude-install.sh
  rm -f /tmp/claude-install.sh
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

  # Install for bash if .bashrc exists
  if [ -f "$HOME/.bashrc" ] && ! grep -q "alias-suggest" "$HOME/.bashrc" 2>/dev/null; then
    echo "Installing shell-alias-suggestions hooks for bash..."
    alias-suggest install --bash
  fi

  # Install for zsh if .zshrc exists
  if [ -f "$HOME/.zshrc" ] && ! grep -q "alias-suggest" "$HOME/.zshrc" 2>/dev/null; then
    echo "Installing shell-alias-suggestions hooks for zsh..."
    alias-suggest install --zsh
  fi

  echo "shell-alias-suggestions installation completed"
else
  echo "uv not found, skipping shell-alias-suggestions installation"
fi

echo "Devcontainer configuration completed"
