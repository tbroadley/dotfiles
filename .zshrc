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

# zoxide (smart cd)
eval "$(zoxide init zsh)"

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
# Claude wrapper functions that warn if running outside dev container in a dir with devcontainer setup
unalias cl clc clr 2>/dev/null
_claude_in_devcontainer() {
    local claude_cmd="$1"
    shift
    if [[ ! -f /.dockerenv && ( -d .devcontainer || -f .devcontainer.json ) ]]; then
        printf "Warning: Running outside dev container in a directory with devcontainer setup.\nRun on host anyway? [y/N] "
        read -r reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            claude $claude_cmd "$@"
        else
            printf "Launch dev container and run claude there? [Y/n] "
            read -r reply2
            if [[ ! "$reply2" =~ ^[Nn]$ ]]; then
                source ~/dotfiles/devc.zsh
                _devc_claude "$claude_cmd" "$@"
            fi
        fi
    else
        claude $claude_cmd "$@"
    fi
}
cl() { _claude_in_devcontainer "" "$@"; }
clc() { _claude_in_devcontainer "--continue" "$@"; }
clr() { _claude_in_devcontainer "--resume" "$@"; }

# Completions
autoload -Uz compinit && compinit

# Git branch in prompt (vcs_info)
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
RPROMPT='${vcs_info_msg_0_}'
zstyle ':vcs_info:git:*' formats '%b'
PROMPT='%1~ %# '

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

# Run install.sh in all dev containers (parallel)
dotfiles-sync() {
    local containers=("${(@f)$(docker ps --format '{{.Names}}' | grep -i dev)}")
    if [[ ${#containers[@]} -eq 0 || -z "${containers[1]}" ]]; then
        echo "No running dev containers found"
        return 1
    fi

    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    # Sync a single container (runs in subshell, writes to log file)
    # Exit code is written to .exit file
    _sync_one() {
        local container=$1
        local logfile="$tmpdir/$container.log"
        local exitfile="$tmpdir/$container.exit"
        (
            echo "=== $container ==="
            # Find non-root user (UID >= 1000)
            local user=$(docker exec "$container" awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
            if [[ -z "$user" ]]; then
                echo "  No non-root user found, skipping"
                exit 0
            fi
            echo "  User: $user"
            # Check if dotfiles repo exists
            if ! docker exec "$container" test -f "/home/$user/dotfiles/install.sh"; then
                echo "  No ~/dotfiles/install.sh found, skipping"
                exit 0
            fi
            if ! docker exec -u "$user" -w "/home/$user/dotfiles" "$container" git pull 2>&1; then
                echo "  git pull failed"
                exit 1
            fi
            if ! docker exec -u "$user" -w "/home/$user/dotfiles" "$container" ./install.sh 2>&1; then
                echo "  install.sh failed"
                exit 1
            fi
            echo "  Done"
        ) > "$logfile" 2>&1
        echo $? > "$exitfile"
    }

    echo "Syncing ${#containers[@]} containers in parallel..."
    echo ""

    # Launch all syncs in parallel
    for container in "${containers[@]}"; do
        _sync_one "$container" &
    done

    # Wait for all background jobs
    wait

    # Collect results and print output
    local errors=()
    for container in "${containers[@]}"; do
        cat "$tmpdir/$container.log"
        local exit_code=$(cat "$tmpdir/$container.exit" 2>/dev/null || echo 1)
        if [[ "$exit_code" -ne 0 ]]; then
            errors+=("$container")
        fi
    done

    # Print error summary if any
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        echo "=== ERROR SUMMARY ==="
        for err in "${errors[@]}"; do
            echo "  FAILED: $err"
        done
        return 1
    fi

    echo ""
    echo "All containers synced successfully"
}

# Dev container functions (auto-reload from devc.zsh before running)
source ~/dotfiles/devc.zsh
unalias dc dcr 2>/dev/null

dc() {
    source ~/dotfiles/devc.zsh
    devc "$@"
}

dcr() {
    source ~/dotfiles/devc.zsh
    devc --rebuild "$@"
}

# wt - git worktree helper with completion
source ~/dotfiles/bin/wt.bash

# Local config (secrets, machine-specific settings)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# >>> alias-suggest initialize >>>
eval "$(alias-suggest hook)"
# <<< alias-suggest initialize <<<
