#!/bin/bash
set -euo pipefail

# Devcontainer dotfiles setup script
# Runs inside the container when VS Code/Cursor opens a devcontainer
# All installations are user-local, no root access required

echo "Setting up devcontainer dotfiles..."

# Track failed background jobs
declare -A FAILED_JOBS=()
declare -A JOB_PIDS=()
declare -A JOB_OUTPUT_FILES=()
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Report any failures at the end
report_failures() {
  if [ ${#FAILED_JOBS[@]} -gt 0 ]; then
    echo ""
    echo "========================================"
    echo "FAILED INSTALLATIONS:"
    echo "========================================"
    for name in "${!FAILED_JOBS[@]}"; do
      local output_file="${FAILED_JOBS[$name]}"
      echo ""
      echo "--- $name ---"
      if [ -f "$output_file" ]; then
        cat "$output_file"
      else
        echo "(no output captured)"
      fi
    done
    echo "========================================"
    return 1
  fi
  return 0
}

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

# Remove lines matching patterns from shell rc files
remove_from_rc() {
  for pattern in "$@"; do
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [ -f "$rc_file" ] && grep -qF "$pattern" "$rc_file" 2>/dev/null; then
        grep -vF "$pattern" "$rc_file" > "$rc_file.tmp" && mv "$rc_file.tmp" "$rc_file"
      fi
    done
  done
}

# Aliases (work in both shells)
add_to_rc "alias b=basedpyright" "alias b=basedpyright"
add_to_rc "claude()" 'claude() { ANTHROPIC_API_KEY= ANTHROPIC_BASE_URL= command claude "$@"; }'
add_to_rc "alias dotfiles=" "alias dotfiles='git -C ~/dotfiles pull && ~/dotfiles/install.sh && exec \$SHELL'"
add_to_rc "alias g=git" "alias g=git"
add_to_rc "alias ppl=" "alias ppl='pivot pull'"
add_to_rc "alias pps=" "alias pps='pivot push'"
add_to_rc "alias pco=" "alias pco='pivot checkout'"
# pr: pivot repro (no stage names) or pivot run (with stage names)
# Stage names are positional args that don't start with --
remove_from_rc 'alias pr='
add_to_rc "pr()" 'pr() { local has_stage=false; for arg in "$@"; do [[ "$arg" != --* ]] && has_stage=true && break; done; if $has_stage; then pivot run "$@"; else pivot repro "$@"; fi; }'
# pla/psa: detect pivot vs dvc and use the appropriate tool
# Remove old alias versions that conflict with the function definitions
remove_from_rc 'alias pla=' 'alias psa='
add_to_rc "pla()" 'pla() { git pull && if command -v pivot &>/dev/null; then pivot pull; elif command -v dvc &>/dev/null; then dvc pull; fi; }'
add_to_rc "psa()" 'psa() { if command -v pivot &>/dev/null; then pivot push; elif command -v dvc &>/dev/null; then dvc push; fi && git push; }'
add_to_rc "alias pt=pytest" "alias pt=pytest"
add_to_rc "alias r=ruff" "alias r=ruff"
add_to_rc "alias v=vim" "alias v=vim"
add_to_rc "alias cl=claude" "alias cl=claude"
add_to_rc "alias clc=" "alias clc='claude --continue'"
add_to_rc "alias clr=" "alias clr='claude --resume'"
add_to_rc "alias codex=" "alias codex='codex --add-dir /opt/python'"
add_to_rc "alias cx=" "alias cx='codex --add-dir /opt/python'"
add_to_rc "export ANTHROPIC_MODEL=opus" "export ANTHROPIC_MODEL=opus"
add_to_rc "export PYTHON_KEYRING_BACKEND=" "export PYTHON_KEYRING_BACKEND=keyrings.alt.file.PlaintextKeyring"
add_to_rc "export EDITOR=vim" "export EDITOR=vim"
# Persist host timezone if forwarded via TZ env var
if [ -n "${TZ:-}" ]; then
  # Remove any old TZ export before adding the current one
  remove_from_rc "export TZ="
  add_to_rc "export TZ=" "export TZ=$TZ"
fi
add_to_rc "export DD_SITE=" "export DD_SITE=us3.datadoghq.com"
add_to_rc "export DD_TOKEN_STORAGE=" "export DD_TOKEN_STORAGE=file"
add_to_rc "export LANG=en_US.UTF-8" "export LANG=en_US.UTF-8"
add_to_rc "export LC_ALL=en_US.UTF-8" "export LC_ALL=en_US.UTF-8"
add_to_rc 'export PATH="$HOME/.local/bin:$PATH"' 'export PATH="$HOME/.local/bin:$PATH"'
add_to_rc 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi' 'if [[ "$TERM_PROGRAM" == "vscode" && -f ".env" ]]; then set -a; source .env; set +a; fi'

# Set PYTHONPATH to git root (updates on directory change, useful for worktrees)
# Use a function to avoid PROMPT_COMMAND semicolon issues with zoxide/alias-suggest
# Strip trailing semicolon before appending to handle inconsistent PROMPT_COMMAND formats
add_to_rc '__set_pythonpath_to_git_root()' '__set_pythonpath_to_git_root() { export PYTHONPATH="$(git rev-parse --show-toplevel 2>/dev/null || echo $PYTHONPATH)"; }
PROMPT_COMMAND="${PROMPT_COMMAND%;}"; PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}__set_pythonpath_to_git_root"' true false

# Bash-specific completions
add_to_rc "source /etc/bash_completion.d/git-prompt" "source /etc/bash_completion.d/git-prompt 2>/dev/null" true false
add_to_rc "source /usr/share/bash-completion/completions/git" "source /usr/share/bash-completion/completions/git 2>/dev/null" true false
add_to_rc "__git_complete g __git_main" "__git_complete g __git_main 2>/dev/null" true false

# wt - git worktree helper with completion
add_to_rc "source ~/dotfiles/bin/wt.bash" "source ~/dotfiles/bin/wt.bash" true false

# Zsh-specific setup
add_to_rc "autoload -Uz compinit && compinit" "autoload -Uz compinit && compinit" false true
add_to_rc "autoload -Uz vcs_info" "autoload -Uz vcs_info" false true

# wt - git worktree helper with completion (zsh)
add_to_rc "source ~/dotfiles/bin/wt.bash" "source ~/dotfiles/bin/wt.bash" false true

# Zoxide shell initialization (enables 'z' command for smart directory jumping)
add_to_rc 'eval "$(zoxide init bash)"' 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"' true false
add_to_rc 'eval "$(zoxide init zsh)"' 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"' false true

echo "shell rc configured"

# Ensure ~/.local/bin exists and is in PATH
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Define installation functions for parallel execution
install_ripgrep() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "Skipping ripgrep (not Linux)"
    return 0
  fi
  if command -v rg >/dev/null 2>&1; then
    echo "ripgrep is already installed: $(rg --version | head -1)"
    return 0
  fi

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
    *) echo "Unsupported architecture for ripgrep: $ARCH"; return 1 ;;
  esac

  RG_VERSION="14.1.1"
  local tmp_file="/tmp/rg-$$.tar.gz"
  local tmp_dir="/tmp/rg-$$"
  wget -q -O "$tmp_file" "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${RG_ARCH}.tar.gz"
  verify_checksum "$tmp_file" "$RG_CHECKSUM"
  mkdir -p "$tmp_dir"
  tar -xzf "$tmp_file" -C "$tmp_dir" --strip-components=1
  mv "$tmp_dir/rg" "$HOME/.local/bin/"
  rm -rf "$tmp_file" "$tmp_dir"
  chmod +x "$HOME/.local/bin/rg"
  echo "ripgrep installation completed"
}

install_jq() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "Skipping jq (not Linux)"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    echo "jq is already installed: $(jq --version)"
    return 0
  fi

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
    *) echo "Unsupported architecture for jq: $ARCH"; return 1 ;;
  esac

  JQ_VERSION="1.7.1"
  local tmp_file="/tmp/jq-$$"
  wget -q -O "$tmp_file" "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${JQ_ARCH}"
  verify_checksum "$tmp_file" "$JQ_CHECKSUM"
  mv "$tmp_file" "$HOME/.local/bin/jq"
  chmod +x "$HOME/.local/bin/jq"
  echo "jq installation completed"
}

install_gh() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "Skipping gh CLI (not Linux)"
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    echo "gh CLI is already installed: $(gh --version | head -1)"
    return 0
  fi

  echo "Installing gh CLI..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      GH_ARCH="linux_amd64"
      GH_CHECKSUM="ca6e7641214fbd0e21429cec4b64a7ba626fd946d8f9d6d191467545b092015e"
      ;;
    aarch64|arm64)
      GH_ARCH="linux_arm64"
      GH_CHECKSUM="b1a0c0a0fcf18524e36996caddc92a062355ed014defc836203fe20fba75a38e"
      ;;
    *) echo "Unsupported architecture for gh: $ARCH"; return 1 ;;
  esac

  GH_VERSION="2.83.2"
  local tmp_file="/tmp/gh-$$.tar.gz"
  local tmp_dir="/tmp/gh-$$"
  wget -q -O "$tmp_file" "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz"
  verify_checksum "$tmp_file" "$GH_CHECKSUM"
  mkdir -p "$tmp_dir"
  tar -xzf "$tmp_file" -C "$tmp_dir" --strip-components=1
  mv "$tmp_dir/bin/gh" "$HOME/.local/bin/"
  rm -rf "$tmp_file" "$tmp_dir"
  chmod +x "$HOME/.local/bin/gh"
  echo "gh CLI installation completed"
}

install_zoxide() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "Skipping zoxide (not Linux)"
    return 0
  fi
  if command -v zoxide >/dev/null 2>&1; then
    echo "zoxide is already installed: $(zoxide --version)"
    return 0
  fi

  echo "Installing zoxide..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      ZOXIDE_ARCH="x86_64-unknown-linux-musl"
      ZOXIDE_CHECKSUM="4092ee38aa1efde42e4efb2f9c872df5388198aacae7f1a74e5eb5c3cc7f531c"
      ;;
    aarch64|arm64)
      ZOXIDE_ARCH="aarch64-unknown-linux-musl"
      ZOXIDE_CHECKSUM="078cc9cc8cedb6c45edb84c0f5bad53518c610859c73bdb3009a52b89652c103"
      ;;
    *) echo "Unsupported architecture for zoxide: $ARCH"; return 1 ;;
  esac

  ZOXIDE_VERSION="0.9.8"
  local tmp_file="/tmp/zoxide-$$.tar.gz"
  local tmp_dir="/tmp/zoxide-$$"
  wget -q -O "$tmp_file" "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}.tar.gz"
  verify_checksum "$tmp_file" "$ZOXIDE_CHECKSUM"
  mkdir -p "$tmp_dir"
  tar -xzf "$tmp_file" -C "$tmp_dir"
  mv "$tmp_dir/zoxide" "$HOME/.local/bin/"
  rm -rf "$tmp_file" "$tmp_dir"
  chmod +x "$HOME/.local/bin/zoxide"
  echo "zoxide installation completed"
}

install_pup() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "Skipping pup (not Linux)"
    return 0
  fi
  if command -v pup >/dev/null 2>&1; then
    echo "pup is already installed: pup $(pup --version 2>&1 | head -1)"
    return 0
  fi

  echo "Installing pup..."
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      PUP_ARCH="Linux_x86_64"
      PUP_CHECKSUM="7f2a347c2b34ecf3cec4facae7528a4e36279f61b68c989a477f7c5ab312dbe6"
      ;;
    aarch64|arm64)
      PUP_ARCH="Linux_arm64"
      PUP_CHECKSUM="186dcb5318a5efd066418b54285c362ecd270a54fa764d506a2b59093a657b55"
      ;;
    *) echo "Unsupported architecture for pup: $ARCH"; return 1 ;;
  esac

  PUP_VERSION="0.9.2"
  local tmp_file="/tmp/pup-$$.tar.gz"
  local tmp_dir="/tmp/pup-$$"
  wget -q -O "$tmp_file" "https://github.com/DataDog/pup/releases/download/v${PUP_VERSION}/pup_${PUP_VERSION}_${PUP_ARCH}.tar.gz"
  verify_checksum "$tmp_file" "$PUP_CHECKSUM"
  mkdir -p "$tmp_dir"
  tar -xzf "$tmp_file" -C "$tmp_dir"
  mv "$tmp_dir/pup" "$HOME/.local/bin/"
  rm -rf "$tmp_file" "$tmp_dir"
  chmod +x "$HOME/.local/bin/pup"
  echo "pup installation completed"
}

install_nvm_and_node() {
  # Check common nvm locations (devcontainer images often have it pre-installed elsewhere)
  if [ -s "/usr/local/share/nvm/nvm.sh" ]; then
    export NVM_DIR="/usr/local/share/nvm"
  else
    export NVM_DIR="$HOME/.nvm"
  fi

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "Installing nvm..."
    NVM_VERSION="0.40.1"
    NVM_CHECKSUM="abdb525ee9f5b48b34d8ed9fc67c6013fb0f659712e401ecd88ab989b3af8f53"
    local tmp_file="/tmp/nvm-install-$$.sh"
    curl -fsSL -o "$tmp_file" "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
    verify_checksum "$tmp_file" "$NVM_CHECKSUM"
    bash "$tmp_file"
    rm -f "$tmp_file"
  fi

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
}

install_claude_code() {
  # Check if already installed as a native binary (not the node/npm version)
  if command -v claude >/dev/null 2>&1; then
    local claude_path
    claude_path="$(command -v claude)"
    # Resolve symlinks to get the actual binary
    if [ -L "$claude_path" ]; then
      claude_path="$(readlink -f "$claude_path")"
    fi
    if file "$claude_path" 2>/dev/null | grep -q "ELF"; then
      echo "Claude Code (native) is already installed: $(claude --version)"
      return 0
    fi
    echo "Claude Code is installed via Node/npm, replacing with native installer..."
    # Remove the npm installation
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  fi

  echo "Installing Claude Code (native)..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "Claude Code installation completed"
}

install_shell_alias_suggestions() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found, skipping shell-alias-suggestions installation"
    return 0
  fi

  echo "Installing/upgrading shell-alias-suggestions..."
  uv tool install --upgrade git+https://github.com/tbroadley/shell-alias-suggestions.git

  if [ -f "$HOME/.bashrc" ] && ! grep -q "alias-suggest" "$HOME/.bashrc" 2>/dev/null; then
    echo "Installing shell-alias-suggestions hooks for bash..."
    alias-suggest install --bash
  fi

  if [ -f "$HOME/.zshrc" ] && ! grep -q "alias-suggest" "$HOME/.zshrc" 2>/dev/null; then
    echo "Installing shell-alias-suggestions hooks for zsh..."
    alias-suggest install --zsh
  fi

  echo "shell-alias-suggestions installation completed"
}

# Export functions and variables for subshells
export -f verify_checksum
export -f install_ripgrep install_jq install_gh install_zoxide install_pup install_nvm_and_node
export -f install_claude_code install_shell_alias_suggestions
export HOME SCRIPT_DIR

# Phase 1: Run independent installations in parallel
echo "Starting Phase 1 installations (parallel)..."

# Start background jobs and track PIDs
for job_name in ripgrep jq gh zoxide pup nvm claude-code shell-alias-suggestions; do
  output_file="$TEMP_DIR/${job_name}.out"
  JOB_OUTPUT_FILES["$job_name"]="$output_file"
  case "$job_name" in
    ripgrep)                 install_ripgrep > "$output_file" 2>&1 & ;;
    jq)                      install_jq > "$output_file" 2>&1 & ;;
    gh)                      install_gh > "$output_file" 2>&1 & ;;
    zoxide)                  install_zoxide > "$output_file" 2>&1 & ;;
    pup)                     install_pup > "$output_file" 2>&1 & ;;
    nvm)                     install_nvm_and_node > "$output_file" 2>&1 & ;;
    claude-code)             install_claude_code > "$output_file" 2>&1 & ;;
    shell-alias-suggestions) install_shell_alias_suggestions > "$output_file" 2>&1 & ;;
  esac
  JOB_PIDS["$job_name"]=$!
done

# Wait for all parallel jobs and collect failures
for job_name in "${!JOB_PIDS[@]}"; do
  pid="${JOB_PIDS[$job_name]}"
  output_file="${JOB_OUTPUT_FILES[$job_name]}"
  if ! wait "$pid"; then
    FAILED_JOBS["$job_name"]="$output_file"
  fi
done

# Print output from successful jobs
for job_name in ripgrep jq gh zoxide pup nvm claude-code shell-alias-suggestions; do
  output_file="${JOB_OUTPUT_FILES[$job_name]}"
  # Check if job_name exists in FAILED_JOBS array
  if [ -f "$output_file" ] && ! [[ -v "FAILED_JOBS[$job_name]" ]]; then
    cat "$output_file"
  fi
done

echo "Phase 1 installations completed"

# Re-source nvm after parallel install (needed for npm commands)
if [ -s "/usr/local/share/nvm/nvm.sh" ]; then
  export NVM_DIR="/usr/local/share/nvm"
else
  export NVM_DIR="$HOME/.nvm"
fi
set +u
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
set -u

# Add dotfiles bin to PATH and create symlinks for renamed scripts
add_to_rc 'export PATH="$HOME/dotfiles/bin:$PATH"' 'export PATH="$HOME/dotfiles/bin:$PATH"'
ln -sf "$SCRIPT_DIR/bin/cursor-in-container" "$HOME/.local/bin/cursor"
ln -sf "$SCRIPT_DIR/bin/wispr-add-dictionary-remote" "$HOME/.local/bin/wispr-add-dictionary"
add_to_rc 'export BROWSER=open-url-on-host' 'export BROWSER=open-url-on-host'
echo "Dotfiles bin added to PATH"

# Configure Claude Code settings, hooks, and skills (fast, do immediately)
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"
cp -r "$SCRIPT_DIR/claude/"* "$CLAUDE_DIR/"
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true

# Install external skills from GitHub repos
install_external_skills() {
  local skills_dir="$CLAUDE_DIR/skills"
  mkdir -p "$skills_dir"

  # List of external skills: "repo:skill_path:local_name"
  local external_skills=(
    "sjawhar/pivot:skills/writing-pivot-stages:writing-pivot-stages"
  )

  for spec in "${external_skills[@]}"; do
    IFS=':' read -r repo skill_path local_name <<< "$spec"
    local target_dir="$skills_dir/$local_name"
    mkdir -p "$target_dir"

    if gh api "repos/$repo/contents/$skill_path/SKILL.md" 2>/dev/null | jq -r '.content' | base64 -d > "$target_dir/SKILL.md" 2>/dev/null; then
      echo "Installed skill: $local_name (from $repo)"
    else
      echo "Warning: Failed to install skill $local_name from $repo"
    fi
  done
}

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  install_external_skills
else
  echo "Skipping external skills (gh CLI not authenticated)"
fi

echo "Claude Code settings, hooks, and skills installed"

# Configure Codex settings + sync Claude skills into Codex
CODEX_DIR="$HOME/.codex"
mkdir -p "$CODEX_DIR"
if [ -d "$SCRIPT_DIR/codex" ]; then
  ln -sf "$SCRIPT_DIR/codex/config.toml" "$CODEX_DIR/config.toml"
  echo "Codex config installed"
fi

if [ -d "$SCRIPT_DIR/claude/skills" ]; then
  CODEX_SKILLS_DIR="$CODEX_DIR/skills"
  mkdir -p "$CODEX_SKILLS_DIR"
  for skill_dir in "$SCRIPT_DIR/claude/skills"/*; do
    [ -d "$skill_dir" ] || continue
    ln -sfn "$skill_dir" "$CODEX_SKILLS_DIR/$(basename "$skill_dir")"
  done
  echo "Codex skills synced from Claude"
fi

# Configure Gemini CLI settings
GEMINI_DIR="$HOME/.gemini"
mkdir -p "$GEMINI_DIR"
if [ -d "$SCRIPT_DIR/gemini" ]; then
  ln -sf "$SCRIPT_DIR/gemini/settings.json" "$GEMINI_DIR/settings.json"
  echo "Gemini CLI settings installed"
fi

# Configure Claude Code authentication if token is available
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  if [ -f "$HOME/.claude.json" ]; then
    jq '. + {"hasCompletedOnboarding": true}' "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
  else
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
  fi
  echo "Claude Code onboarding bypass configured"
fi

# Define Phase 2 installation functions (depend on Phase 1)
install_codex() {
  # Re-source nvm (needed in subshell)
  if [ -s "/usr/local/share/nvm/nvm.sh" ]; then
    export NVM_DIR="/usr/local/share/nvm"
  else
    export NVM_DIR="$HOME/.nvm"
  fi
  set +u
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  set -u

  if npm list -g @openai/codex >/dev/null 2>&1; then
    echo "@openai/codex is already installed globally"
  else
    echo "Installing @openai/codex globally..."
    npm install -g @openai/codex
  fi
}

setup_gh_auth() {
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "GH_TOKEN not set, skipping GitHub CLI authentication"
    return 0
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Authenticating GitHub CLI with GH_TOKEN..."
    echo "$GH_TOKEN" | gh auth login --with-token
  fi

  gh auth setup-git
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/"
  echo "GitHub CLI git credential helper configured"
}

export -f install_codex setup_gh_auth

# Phase 2: Run npm-dependent and gh-auth in parallel
echo "Starting Phase 2 installations (parallel)..."

declare -A PHASE2_PIDS=()
declare -A PHASE2_OUTPUT=()

for job_name in codex gh-auth; do
  output_file="$TEMP_DIR/${job_name}.out"
  PHASE2_OUTPUT["$job_name"]="$output_file"
  case "$job_name" in
    codex)   install_codex > "$output_file" 2>&1 & ;;
    gh-auth) setup_gh_auth > "$output_file" 2>&1 & ;;
  esac
  PHASE2_PIDS["$job_name"]=$!
done

# Wait for Phase 2 and collect failures
for job_name in "${!PHASE2_PIDS[@]}"; do
  pid="${PHASE2_PIDS[$job_name]}"
  output_file="${PHASE2_OUTPUT[$job_name]}"
  if ! wait "$pid"; then
    FAILED_JOBS["$job_name"]="$output_file"
  fi
done

# Print output from Phase 2 jobs
for job_name in codex gh-auth; do
  output_file="${PHASE2_OUTPUT[$job_name]}"
  if [ -f "$output_file" ] && ! [[ -v "FAILED_JOBS[$job_name]" ]]; then
    cat "$output_file"
  fi
done

echo "Phase 2 installations completed"

# Phase 3: Install Claude Code plugins (requires both gh auth and claude)
if [ -n "${GH_TOKEN:-}" ] && command -v claude >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Installing Claude Code plugins..."
  GITHUB_TOKEN="$GH_TOKEN" claude plugin marketplace add METR/eval-execution-claude 2>/dev/null || true
  GITHUB_TOKEN="$GH_TOKEN" claude plugin marketplace add huggingface/skills 2>/dev/null || true
  claude plugin install warehouse-query 2>/dev/null || true
  claude plugin install hugging-face-cli@huggingface-skills 2>/dev/null || true
  claude plugin install hugging-face-datasets@huggingface-skills 2>/dev/null || true
  echo "Claude Code plugins installed"
fi

# Report any failures from parallel installations
if ! report_failures; then
  echo ""
  echo "Some installations failed. See errors above."
  exit 1
fi

echo "Devcontainer configuration completed"
