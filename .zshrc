# History search with arrow keys
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

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

# Local binaries (apf, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Dotfiles scripts (iterate)
export PATH="$HOME/dotfiles/bin:$PATH"

# Aliases
alias c=clear
alias d=docker
alias g=git
alias k=kubectl
alias kc='kubectl config use-context'
alias psa='dvc push && git push'
alias tf=terraform
alias v=vim
alias cl=claude
alias clc='claude --continue'
alias clr='claude --resume'
alias oc=opencode
alias awsl='aws sso login'

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

# Run install.sh in all dev containers (parallel)
dotfiles-sync() {
    # Restart url-listener to pick up any changes
    echo "Restarting url-listener..."
    pkill -f "url-listener" 2>/dev/null
    nohup ~/dotfiles/bin/url-listener >/dev/null 2>&1 &
    disown
    echo "url-listener restarted (PID $!)"
    echo ""

    local containers=("${(@f)$(docker ps --format '{{.Names}}' | grep -i dev)}")
    if [[ ${#containers[@]} -eq 0 || -z "${containers[1]}" ]]; then
        echo "No running dev containers found"
        return 0
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

# start - spin up a dev container and start claude on a task
# Usage: start <project> <task description...>
# Example: start mon "fix the flaky monitoring test"
# Requires ANTHROPIC_API_KEY in environment (e.g. .zshrc.local)
start() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: start <project> <task description...>"
        return 1
    fi

    local project="$1"; shift
    local task="$*"

    # Generate branch name via Anthropic API (Haiku for speed)
    echo "Generating branch name..."
    local branch
    branch=$(curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n --arg task "$task" '{
            model: "claude-haiku-4-5-20251001",
            max_tokens: 30,
            messages: [{role: "user", content: ("Output ONLY a short kebab-case git branch name. No quotes, no prefix. Task: " + $task)}]
        }')" | jq -r '.content[0].text')

    if [[ -z "$branch" || "$branch" == "null" ]]; then
        echo "Failed to generate branch name"
        return 1
    fi

    # Clean up any whitespace/quotes the model might add
    branch=$(echo "$branch" | tr -d '"'\'' \n' | head -c 60)
    echo "Branch: $branch"

    # Resolve project directory with zoxide
    local dir
    dir=$(zoxide query "$project") || { echo "Project not found: $project"; return 1; }
    echo "Project: $dir"
    cd "$dir" || return 1

    if [ -d "$dir/.devcontainer" ]; then
        # Start dev container (setup only, don't enter)
        dc --no-enter || return 1

        # Exec into container: create worktree and start claude with the task
        devcontainer exec --workspace-folder "$PWD" \
            --remote-env "START_BRANCH=$branch" \
            --remote-env "START_TASK=$task" \
            bash -c '
                [ -f ~/.bashrc ] && . ~/.bashrc
                set -a; [ -f .env ] && . .env; set +a
                [ -f /opt/python/bin/activate ] && . /opt/python/bin/activate
                wt "$START_BRANCH" && claude "$START_TASK"
            '
    else
        # No dev container — run locally
        wt "$branch" && claude "$task"
    fi
}

# wt - git worktree helper with completion
source ~/dotfiles/bin/wt.bash

# Local config (secrets, machine-specific settings)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# >>> alias-suggest initialize >>>
eval "$(alias-suggest hook)"
# <<< alias-suggest initialize <<<
