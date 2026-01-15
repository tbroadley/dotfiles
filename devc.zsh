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

    # Todoist token forwarding
    if [ -n "${TODOIST_TOKEN:-}" ]; then
        up_opts+=(--remote-env "TODOIST_TOKEN=$TODOIST_TOKEN")
        exec_opts+=(--remote-env "TODOIST_TOKEN=$TODOIST_TOKEN")
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
    if [[ -n "$container_id" ]]; then
        if command -v apf &> /dev/null; then
            echo "Starting automatic port forwarding..."
            apf "$container_id" &> /dev/null &
            disown
        else
            echo "ERROR: apf not found. Install apf or ensure ~/.local/bin is in PATH." >&2
            return 1
        fi
    fi

    # Restart URL listener to pick up any code changes
    local listener_pid
    listener_pid=$(pgrep -f 'url-listener' 2>/dev/null)
    if [[ -n "$listener_pid" ]]; then
        echo "Restarting URL listener..."
        kill "$listener_pid" 2>/dev/null
    else
        echo "Starting URL listener..."
    fi
    ~/dotfiles/bin/url-listener &>/dev/null &
    disown

    echo "Setting up dotfiles..."
    devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" sh -c '
        if [ -d $HOME/dotfiles ]; then
            cd $HOME/dotfiles && git pull
        else
            git clone https://github.com/tbroadley/dotfiles.git $HOME/dotfiles
        fi
        bash $HOME/dotfiles/install.sh

        # Persist auth tokens in container
        env_file="$HOME/.devcontainer_env"
        : > "$env_file"
        [ -n "${GH_TOKEN:-}" ] && echo "export GH_TOKEN=\"$GH_TOKEN\"" >> "$env_file"
        [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && echo "export CLAUDE_CODE_OAUTH_TOKEN=\"$CLAUDE_CODE_OAUTH_TOKEN\"" >> "$env_file"
        [ -n "${TODOIST_TOKEN:-}" ] && echo "export TODOIST_TOKEN=\"$TODOIST_TOKEN\"" >> "$env_file"

        # Source from bashrc if not already configured
        if ! grep -q "devcontainer_env" "$HOME/.bashrc" 2>/dev/null; then
            echo "[ -f \$HOME/.devcontainer_env ] && . \$HOME/.devcontainer_env" >> "$HOME/.bashrc"
        fi
    '

    echo "Entering container..."
    devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" bash -c '
        # Create a temporary rcfile that sources bashrc then activates venv
        rcfile=$(mktemp)
        cat > "$rcfile" << '\''RCEOF'\''
[ -f ~/.bashrc ] && . ~/.bashrc
set -a
[ -f .env ] && . .env
set +a
[ -f /opt/python/bin/activate ] && . /opt/python/bin/activate
RCEOF
        bash --rcfile "$rcfile"
        rm -f "$rcfile"
    '
}
