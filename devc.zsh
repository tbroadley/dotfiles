devc() {
    local workspace="${PWD}"
    local rebuild_flag=""
    local cmd_args=()

    local no_enter=false

    while [[ "$1" == -* ]]; do
        case "$1" in
            --rebuild|-r)
                rebuild_flag="--remove-existing-container"
                shift
                ;;
            --no-enter|-n)
                no_enter=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ -n "$rebuild_flag" ]]; then
        echo "Rebuilding dev container..."
    else
        echo "Starting dev container..."
    fi

    # Remaining arguments are the command to run inside the container
    cmd_args=("$@")

    # Restart URL listener via launchd (host-side, runs parallel with devcontainer up)
    echo "Restarting URL listener..."
    launchctl kickstart -k gui/$(id -u)/com.thomas.url-listener &>/dev/null &
    local url_listener_pid=$!

    # Get GitHub token in background (gh CLI may take a moment)
    local gh_token_file=$(mktemp)
    gh auth token > "$gh_token_file" 2>/dev/null &
    local gh_token_pid=$!

    # Build auth forwarding options
    local up_opts=()    # for devcontainer up (supports --mount)
    local exec_opts=()  # for devcontainer exec (only --remote-env)

    # Check local env vars (instant) while gh token is fetching
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        up_opts+=(--remote-env "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
        exec_opts+=(--remote-env "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
    fi

    if [ -n "${TODOIST_TOKEN:-}" ]; then
        up_opts+=(--remote-env "TODOIST_TOKEN=$TODOIST_TOKEN")
        exec_opts+=(--remote-env "TODOIST_TOKEN=$TODOIST_TOKEN")
    fi

    # Forward Codex auth cache if present on host
    local codex_auth_file="$HOME/.codex/auth.json"
    local codex_auth_b64=""
    if [ -f "$codex_auth_file" ]; then
        codex_auth_b64=$(base64 < "$codex_auth_file" | tr -d '\n')
        up_opts+=(--remote-env "CODEX_AUTH_JSON_B64=$codex_auth_b64")
        exec_opts+=(--remote-env "CODEX_AUTH_JSON_B64=$codex_auth_b64")
    fi

    # Wait for gh token and add if present
    wait $gh_token_pid 2>/dev/null
    local gh_token=$(cat "$gh_token_file" 2>/dev/null)
    rm -f "$gh_token_file"
    if [[ -n "$gh_token" ]]; then
        up_opts+=(--remote-env "GH_TOKEN=$gh_token")
        exec_opts+=(--remote-env "GH_TOKEN=$gh_token")
    fi

    # Check if container already exists (to know if we need dotfiles setup)
    local container_existed=false
    if docker ps -a -q --filter "label=devcontainer.local_folder=$workspace" | grep -q .; then
        container_existed=true
    fi

    if ! devcontainer up \
        --workspace-folder "$workspace" \
        "${up_opts[@]}" \
        $rebuild_flag; then
        echo "Failed to start dev container"
        return 1
    fi

    # Wait for URL listener setup to complete
    wait $url_listener_pid 2>/dev/null

    # Get container ID and name for port forwarding and Cursor integration
    local container_id container_name
    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$workspace")
    if [[ -n "$container_id" ]]; then
        container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        [[ -n "$container_name" ]] && exec_opts+=(--remote-env "DEVCONTAINER_NAME=$container_name")

        if command -v apf &> /dev/null; then
            echo "Starting automatic port forwarding with watchdog..."
            ( ~/dotfiles/bin/apf-watchdog "$container_id" &>/dev/null & )
            echo "  Logs: ~/.local/log/apf.log"
        else
            echo "ERROR: apf not found. Install apf or ensure ~/.local/bin is in PATH." >&2
            return 1
        fi
    fi

    if [[ -n "$rebuild_flag" || "$container_existed" == "false" ]]; then
        echo "Setting up dotfiles..."
        devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" sh -c '
            if [ -d $HOME/dotfiles ]; then
                cd $HOME/dotfiles && git pull
            else
                git clone https://github.com/tbroadley/dotfiles.git $HOME/dotfiles
            fi
            bash $HOME/dotfiles/install.sh
        '
    fi

    echo "Setting up auth..."
    devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" sh -c '
        if [ -n "${CODEX_AUTH_JSON_B64:-}" ]; then
            mkdir -p "$HOME/.codex"
            echo "$CODEX_AUTH_JSON_B64" | base64 -d > "$HOME/.codex/auth.json"
            chmod 600 "$HOME/.codex/auth.json"
        fi

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

    if [[ "$no_enter" == true ]]; then
        echo "Container ready (--no-enter)."
        return 0
    fi

    if [[ ${#cmd_args[@]} -gt 0 ]]; then
        # Run specified command inside the container
        echo "Running command in container: ${cmd_args[*]}"
        local escaped_args=""
        for arg in "${cmd_args[@]}"; do
            escaped_args="$escaped_args '${arg//\'/\'\\\'\'}'"
        done
        devcontainer exec --workspace-folder "$workspace" "${exec_opts[@]}" bash -c "
            [ -f ~/.bashrc ] && . ~/.bashrc
            set -a
            [ -f .env ] && . .env
            set +a
            [ -f /opt/python/bin/activate ] && . /opt/python/bin/activate
            $escaped_args
        "
    else
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
    fi
}
