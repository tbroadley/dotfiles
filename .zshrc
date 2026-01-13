# Dev container functions and aliases

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

    # Start automatic port forwarding in background
    local container_id
    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$workspace")
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
