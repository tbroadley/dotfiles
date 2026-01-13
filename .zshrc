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

    if ! devcontainer up \
        --workspace-folder "$workspace" \
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

    echo "Setting up dotfiles..."
    devcontainer exec --workspace-folder "$workspace" sh -c '
        if [ -d $HOME/dotfiles ]; then
            cd $HOME/dotfiles && git pull
        else
            git clone https://github.com/tbroadley/dotfiles.git $HOME/dotfiles
        fi
        bash $HOME/dotfiles/install.sh
    '

    echo "Entering container..."
    devcontainer exec --workspace-folder "$workspace" bash -c '
        set -a
        [ -f .env ] && . .env
        set +a
        bash -l
    '
}

alias dc='devc'
alias dcr='devc --rebuild'
