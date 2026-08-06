devc() {
    local workspace="${PWD}"
    local rebuild_flag=""
    local cmd_args=()

    local no_enter=false

    while [[ $# -gt 0 && "$1" == -* ]]; do
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
    disown

    # Get GitHub token in background (gh CLI may take a moment)
    local gh_token_file=$(mktemp)
    gh auth token > "$gh_token_file" 2>/dev/null &
    local gh_token_pid=$!

    # Build auth forwarding options
    local up_opts=()    # for devcontainer up (supports --mount)
    local exec_opts=()  # for devcontainer exec (only --remote-env)

    # Forward Claude Code API key from macOS keychain
    local claude_api_key
    claude_api_key=$(security find-generic-password -s "Claude Code" -w 2>/dev/null)
    if [ -n "$claude_api_key" ]; then
        up_opts+=(--remote-env "ANTHROPIC_API_KEY=$claude_api_key")
        exec_opts+=(--remote-env "ANTHROPIC_API_KEY=$claude_api_key")
    fi

    if [ -n "${LINEAR_API_KEY:-}" ]; then
        up_opts+=(--remote-env "LINEAR_API_KEY=$LINEAR_API_KEY")
        exec_opts+=(--remote-env "LINEAR_API_KEY=$LINEAR_API_KEY")
    fi

    # BW_SESSION is deliberately NOT forwarded. It is not one credential, it is
    # the key to the whole vault: anything in the container can `bw list items`
    # and read every secret I own, METR's and otherwise. Containers run agents
    # with --dangerously-skip-permissions, so that is a very short path from a
    # malicious PR comment to the whole vault.
    #
    # A container that needs one specific field asks for it the way remote hosts
    # do: `with-secret FIELD -- command`, which the broker on this laptop
    # authenticates, checks against an allowlist the container cannot edit, and
    # puts in front of me to approve. See bin/credential-broker.

    # The url-listener bearer token. Unlike the vault session above, this is
    # scoped to exactly what the container already needs the listener for —
    # clipboard, opening a URL, notifications — so forwarding it grants nothing
    # the container did not have when those endpoints were unauthenticated.
    local url_listener_token
    url_listener_token="${URL_LISTENER_TOKEN:-$("$HOME/dotfiles/bin/url-listener-token" 2>/dev/null)}"
    if [ -n "$url_listener_token" ]; then
        up_opts+=(--remote-env "URL_LISTENER_TOKEN=$url_listener_token")
        exec_opts+=(--remote-env "URL_LISTENER_TOKEN=$url_listener_token")
    else
        echo "Warning: no url-listener token; clipboard/notify/open forwarding will 401 in the container." >&2
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

    # Detect host timezone and forward to container
    local host_tz=""
    if [[ "$(uname)" == "Darwin" ]]; then
        host_tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    elif [[ -f /etc/timezone ]]; then
        host_tz=$(cat /etc/timezone)
    elif [[ -n "${TZ:-}" ]]; then
        host_tz="$TZ"
    fi
    if [[ -n "$host_tz" ]]; then
        up_opts+=(--remote-env "TZ=$host_tz")
        exec_opts+=(--remote-env "TZ=$host_tz")
    fi

    # Forward the host SSH agent so agents in the container can sign commits with
    # our SSH signing key (private key stays on the host; see gitconfig). Both
    # Docker Desktop and OrbStack expose the host agent at this magic socket path.
    # NOTE: the bind mount is applied at container creation, so an existing
    # container must be rebuilt (devc -r) to pick up agent forwarding.
    local ssh_agent_sock="/ssh-agent.sock"
    up_opts+=(--mount "type=bind,source=/run/host-services/ssh-auth.sock,target=$ssh_agent_sock")
    up_opts+=(--remote-env "SSH_AUTH_SOCK=$ssh_agent_sock")
    exec_opts+=(--remote-env "SSH_AUTH_SOCK=$ssh_agent_sock")

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

    # Get container name for Cursor integration.
    #
    # There is deliberately no automatic port forwarding here. This used to run
    # apf, which discovers every listening socket in the container and opens a
    # matching host listener for each one -- on 0.0.0.0, with no allowlist and
    # no opt-in. That put anything a container happened to serve (Postgres, ssh,
    # Streamlit, the editor server) on whatever wifi the laptop was joined to.
    # Same bug as url-listener's old 0.0.0.0 bind, but automatic and unbounded.
    #
    # To reach a container port, forward exactly the one you want, to loopback:
    #     docker exec ... / ssh -L, or publish with -p 127.0.0.1:PORT:PORT
    local container_id container_name
    container_id=$(docker ps -q --filter "label=devcontainer.local_folder=$workspace")
    if [[ -n "$container_id" ]]; then
        container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///')
        [[ -n "$container_name" ]] && exec_opts+=(--remote-env "DEVCONTAINER_NAME=$container_name")
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
        # It holds bearer tokens, so create it private and keep it that way —
        # the same discipline as ~/.codex/auth.json above. `: >` alone leaves it
        # at whatever the container umask says, usually world-readable.
        : > "$env_file"
        chmod 600 "$env_file"
        [ -n "${GH_TOKEN:-}" ] && echo "export GH_TOKEN=\"$GH_TOKEN\"" >> "$env_file"
        [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\"" >> "$env_file"

        [ -n "${LINEAR_API_KEY:-}" ] && echo "export LINEAR_API_KEY=\"$LINEAR_API_KEY\"" >> "$env_file"
        [ -n "${URL_LISTENER_TOKEN:-}" ] && echo "export URL_LISTENER_TOKEN=\"$URL_LISTENER_TOKEN\"" >> "$env_file"
        [ -n "${TZ:-}" ] && echo "export TZ=\"$TZ\"" >> "$env_file"
        [ -n "${SSH_AUTH_SOCK:-}" ] && echo "export SSH_AUTH_SOCK=\"$SSH_AUTH_SOCK\"" >> "$env_file"

        # Source from shell rc files if not already configured
        if ! grep -q "devcontainer_env" "$HOME/.bashrc" 2>/dev/null; then
            echo "[ -f \$HOME/.devcontainer_env ] && . \$HOME/.devcontainer_env" >> "$HOME/.bashrc"
        fi
        if [ -f "$HOME/.zshrc" ] && ! grep -q "devcontainer_env" "$HOME/.zshrc" 2>/dev/null; then
            echo "[ -f \$HOME/.devcontainer_env ] && . \$HOME/.devcontainer_env" >> "$HOME/.zshrc"
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
