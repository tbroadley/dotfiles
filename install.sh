#!/bin/bash
set -euo pipefail

# Devcontainer dotfiles setup script
# Runs inside the container when VS Code/Cursor opens a devcontainer

echo "Setting up devcontainer dotfiles..."

# Install packages
sudo apt-get update && sudo apt-get install -y vim ripgrep unzip

# Setup inputrc for history search
setup_inputrc() {
  local inputrc_file="$1"
  local owner="$2"

  if [ -f "$inputrc_file" ] && grep -q "history-search-backward" "$inputrc_file"; then
    return 0
  fi

  sudo tee -a "$inputrc_file" > /dev/null << 'EOF'
## arrow up
"\e[A":history-search-backward
## arrow down
"\e[B":history-search-forward
EOF

  if [ -n "$owner" ]; then
    sudo chown "$owner:$owner" "$inputrc_file"
  fi
}

setup_inputrc "/etc/inputrc" ""
setup_inputrc "$HOME/.inputrc" "$USER"

# Setup gitconfig
cat > "$HOME/.gitconfig" << 'EOF'
[user]
	name = Thomas Broadley
	email = thomas@metr.org
[alias]
	a = add
	aa = commit --amend --no-edit -a
	alias = "!f() { git config --global alias.${1} \"${2}\"; }; f"
	amend = commit --amend --no-edit
	amend-all = commit --amend --no-edit -a
	amend-author = commit --amend --reset-author --no-edit
	amend-msg = commit --amend
	ap = add --patch
	b = branch
	ba = branch --all
	bd = "!f() { CURRBRANCH=`git rev-parse --abbrev-ref HEAD`; if [ -z ${1} ]; then git co main; else git co ${1}; fi; git b -D ${CURRBRANCH} && git pull; }; f"
	bm = branch -m
	br = branch -r
	cam = commit -am
	cb = checkout -b
	cl = "!f() { git clone git@github.com:${1}/${2} $HOME/Documents/src/${2}; }; f"
	cm = commit -m
	cmt = commit --all --message "cmt"
	co = checkout
	co-remote = "!f() { git fetch ${1} ${2} && git checkout --track remotes/${1}/${2}; }; f"
	com = checkout master
	cor = "!f() { git co origin/${1}; }; f"
	cp = cherry-pick
	cpa = cherry-pick --abort
	cpc = cherry-pick --continue
	d = diff
	dc = diff --cached
	dh = "!f() { if [ -z ${1} ]; then git diff HEAD; else git diff HEAD~${1}; fi; }; f"
	do = "!f() { git diff origin/$(git rev-parse --abbrev-ref HEAD); }; f"
	ds = diff --stat
	dsh = "!f() { if [ -z ${1} ]; then git diff --stat HEAD; else git diff --stat HEAD~${1}; fi; }; f"
	ec = config --edit --global
	f = fetch
	fixb = "!f() { git b ${1}; git reset --hard HEAD~${2} && git co ${1}; }; f"
	fixup = "!f() { CURRBRANCH=`git rev-parse --abbrev-ref HEAD`; RESETTO=`git merge-base master ${CURRBRANCH}`; COMMITMSG=`git rev-list --format=%B master..${CURRBRANCH} | tail -2`; git reset ${RESETTO}; git add .; git commit -m \"${COMMITMSG}\"; }; f"
	ghc = "!f() { git clone git@github.com:${1}.git; }; f"
	gone = ! "git checkout main && git pull && git branch --format '%(refname:short) %(upstream:track)' | awk '$2 == \"[gone]\" {print $1}' | xargs -r git branch -D"
	i = init
	l = log
	last-commit = log HEAD^..HEAD
	lc = log HEAD^..HEAD
	m = merge
	ma = merge --abort
	mc = merge --continue
	mm = "!f() { git fetch origin main:main && if git merge-base --is-ancestor main HEAD; then echo \"Already up-to-date with main\"; else git merge main && git push; fi; }; f"
	pf = push --force-with-lease
	pl = pull
	ps = push
	pst = push --tags
	rb = rebase
	rba = rebase --abort
	rbc = rebase --continue
	rbs = rebase --skip
	rh = "!f() { if [ -z ${1} ]; then git reset HEAD; else git reset HEAD~${1}; fi; }; f"
	rho = "!f() { CURRBRANCH=`git rev-parse --abbrev-ref HEAD`; git reset --hard origin/${CURRBRANCH}; }; f"
	ri = rebase -i
	rp = reset --patch
	rv = revert
	rvc = revert --continue
	rvh = revert HEAD
	s = status
	smu = "!f() { git submodule update --recursive --remote && git commit --all --message 'Update submodules'; }; f"
	st = stash
	stp = stash pop
	sync = "!f() { git pull && git push; }; f"
	tap = commit --allow-empty -m 'empty commit'
	up = "!f() { CURRBRANCH=`git rev-parse --abbrev-ref HEAD`; git push --set-upstream origin ${CURRBRANCH}; }; f"
[fetch]
	prune = true
[core]
	excludesfile = ~/.gitignore
[push]
	autoSetupRemote = true
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true
[http]
	postBuffer = 157286400
[interactive]
	singleKey = true
EOF

# Setup gitignore
cat > "$HOME/.gitignore" << 'EOF'
.worktrees
.specstory
EOF

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
  sudo apt-get remove -y nodejs npm
  sudo apt-get autoremove -y
  sudo rm -f /etc/apt/sources.list.d/nodesource.list
  sudo rm -f /etc/apt/keyrings/nodesource.gpg
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
  sudo mv /tmp/jj/jj /usr/local/bin/
  rm -rf /tmp/jj.tar.gz /tmp/jj
  sudo chmod +x /usr/local/bin/jj
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
  sudo mv "/tmp/jjui/jjui-${JJUI_VERSION}-linux-${JJUI_ARCH}" /usr/local/bin/jjui
  rm -rf /tmp/jjui.zip /tmp/jjui
  sudo chmod +x /usr/local/bin/jjui
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
