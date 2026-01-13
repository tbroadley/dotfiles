# History search with arrow keys
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Go
export PATH="$PATH:/usr/local/go/bin"
export PATH="$PATH:$HOME/go/bin"

# Cargo/Rust
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# PostgreSQL
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"

# OrbStack
export PATH="$PATH:$HOME/.orbstack/bin"

# Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# Local binaries (apf, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Aliases
alias c=clear
alias d=docker
alias f='pnpm -w fmt && pnpm -w lint'
alias g=git
alias k=kubectl
alias kc='kubectl config use-context'
alias p=pnpm
alias psa='dvc push && git push'
alias t='pnpm -w typecheck'
alias tf=terraform
alias v=vim

# Completions
autoload -Uz compinit && compinit

# Git branch in prompt (vcs_info)
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
RPROMPT='${vcs_info_msg_0_}'
zstyle ':vcs_info:git:*' formats '%b'

# Docker helper functions
ds() {
    docker start $1
}
dsr() {
    ds "$(docker ps -aq --filter=label=runId=$1)"
}
de() {
    ds $1
    docker exec -it $1 bash
}
der() {
    dsr $1
    de "$(docker ps -aq --filter=label=runId=$1)"
}

# Dev container functions
devc() {
    local workspace="${PWD}"
    local rebuild_flag=""

    if [[ "$1" == "--rebuild" || "$1" == "-r" ]]; then
        rebuild_flag="--remove-existing-container"
        echo "Rebuilding dev container..."
    else
        echo "Starting dev container..."
    fi

    # Build auth forwarding options
    local up_opts=()    # for devcontainer up (supports --mount)
    local exec_opts=()  # for devcontainer exec (only --remote-env)

    # GitHub CLI token forwarding (if gh is authenticated)
    # install.sh configures git to rewrite SSH URLs to HTTPS
    local gh_token
    if gh_token=$(gh auth token 2>/dev/null); then
        up_opts+=(--remote-env "GH_TOKEN=$gh_token")
        exec_opts+=(--remote-env "GH_TOKEN=$gh_token")
    fi

    # Claude Code token forwarding
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        up_opts+=(--remote-env "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
        exec_opts+=(--remote-env "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
    fi

    if ! devcontainer up \
        --workspace-folder "$workspace" \
        "${up_opts[@]}" \
        $rebuild_flag; then
        echo "Failed to start dev container"
        return 1
    fi

    # Get container ID and name for port forwarding and Cursor integration
    local container_id container_name
    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$workspace")
    container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
    if [[ -n "$container_name" ]]; then
        exec_opts+=(--remote-env "DEVCONTAINER_NAME=$container_name")
    fi
    if [[ -n "$container_id" ]] && command -v apf &> /dev/null; then
        echo "Starting automatic port forwarding..."
        apf "$container_id" &> /dev/null &
        disown
    fi

    # Start URL listener for browser forwarding (if not already running)
    if ! curl -sf http://localhost:7077/health &>/dev/null; then
        echo "Starting URL listener for browser forwarding..."
        ~/dotfiles/bin/url-listener &>/dev/null &
        disown
    fi

    echo "Setting up dotfiles..."
    devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" sh -c '
        if [ -d $HOME/dotfiles ]; then
            cd $HOME/dotfiles && git pull
        else
            git clone https://github.com/tbroadley/dotfiles.git $HOME/dotfiles
        fi
        bash $HOME/dotfiles/install.sh
    '

    echo "Entering container..."
    devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" bash -c '
        set -a
        [ -f .env ] && . .env
        set +a
        bash -l
    '
}

alias dc='devc'
alias dcr='devc --rebuild'

# Local config (secrets, machine-specific settings)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
