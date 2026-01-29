# wt - create or enter git worktree
# Usage: wt [branch-name | -]
#
# wt           - list all worktrees
# wt -         - cd to the previously selected worktree (like cd -)
# wt <branch>  - if worktree exists, cd into it; otherwise create it
#
# Supports bash and zsh with tab completion for branch names.

# Track the previous worktree directory for "wt -"
_WT_PREVIOUS_DIR=""

wt() {
    local branch="$1"

    # Get the main repo root (not worktree root)
    local repo_root
    repo_root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
        echo "Error: not in a git repository"
        return 1
    }
    # --git-common-dir returns the .git directory, strip it
    repo_root="${repo_root%/.git}"

    # wt with no args: list worktrees
    if [ -z "$branch" ]; then
        git worktree list
        return 0
    fi

    # wt -: switch to previous worktree
    if [ "$branch" = "-" ]; then
        if [ -z "$_WT_PREVIOUS_DIR" ]; then
            echo "Error: no previous worktree directory"
            return 1
        fi
        local old_dir="$PWD"
        cd "$_WT_PREVIOUS_DIR" || return 1
        _WT_PREVIOUS_DIR="$old_dir"
        return 0
    fi

    local worktree_dir="$repo_root/.worktrees/$branch"

    # If worktree already exists in .worktrees/, cd into it
    if [ -d "$worktree_dir" ]; then
        local old_dir="$PWD"
        cd "$worktree_dir" || return 1
        _WT_PREVIOUS_DIR="$old_dir"
        return 0
    fi

    # Check if branch is already checked out in another worktree (e.g., main in repo root)
    local existing_worktree
    existing_worktree=$(git worktree list --porcelain 2>/dev/null | \
        awk -v branch="refs/heads/$branch" '/^worktree /{path=$2} /^branch /{if ($2 == branch) print path}')
    if [ -n "$existing_worktree" ]; then
        local old_dir="$PWD"
        cd "$existing_worktree" || return 1
        _WT_PREVIOUS_DIR="$old_dir"
        return 0
    fi

    # Create .worktrees directory if needed
    mkdir -p "$repo_root/.worktrees"

    # Try to create the worktree
    # First, try checking out existing branch (local or remote-tracking)
    if git worktree add "$worktree_dir" "$branch" 2>/dev/null; then
        : # success
    # If that fails, try creating a new branch tracking the remote
    elif git worktree add "$worktree_dir" -b "$branch" "origin/$branch" 2>/dev/null; then
        : # success, created local branch tracking remote
    # If that also fails, try creating a brand new branch from current HEAD
    elif git worktree add -b "$branch" "$worktree_dir" 2>/dev/null; then
        : # success, created new branch
    else
        echo "Error: failed to create worktree for branch: $branch"
        echo ""
        echo "This can happen if:"
        echo "  - The branch is already checked out in another worktree"
        echo "  - The branch name is invalid"
        echo ""
        echo "Current worktrees:"
        git worktree list
        return 1
    fi

    # Copy .env if it exists in main repo
    [ -f "$repo_root/.env" ] && cp "$repo_root/.env" "$worktree_dir/"

    # Set up DVC cache sharing if DVC is used
    if [ -d "$repo_root/.dvc" ]; then
        mkdir -p "$worktree_dir/.dvc"
        cat > "$worktree_dir/.dvc/config.local" << EOF
[cache]
    dir = $repo_root/.dvc/cache
EOF
    fi

    # Set up Pivot cache sharing if Pivot is used
    if [ -d "$repo_root/.pivot" ]; then
        mkdir -p "$worktree_dir/.pivot"
        # Copy existing config from root repo
        [ -f "$repo_root/.pivot/config.yaml" ] && cp "$repo_root/.pivot/config.yaml" "$worktree_dir/.pivot/"
        # Set cache dir to point to root repo's cache
        (cd "$worktree_dir" && pivot config set cache.dir "$repo_root/.pivot/cache") 2>/dev/null || true
    fi

    # Set up VS Code/Cursor settings to use worktree's venv for Python
    if [ -f "$repo_root/pyproject.toml" ] || [ -f "$repo_root/setup.py" ]; then
        mkdir -p "$worktree_dir/.vscode"
        cat > "$worktree_dir/.vscode/settings.json" << 'EOF'
{
    "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
    "python.analysis.extraPaths": ["${workspaceFolder}"]
}
EOF
    fi

    echo "Worktree created: $worktree_dir"
    local old_dir="$PWD"
    cd "$worktree_dir" || return 1
    _WT_PREVIOUS_DIR="$old_dir"
}

# wtd - delete a git worktree
# Usage: wtd [branch-name]
#
# wtd          - delete the current worktree (if inside .worktrees/)
# wtd <branch> - delete the worktree for <branch>
wtd() {
    local branch="$1"

    # Get the main repo root (not worktree root)
    local repo_root
    repo_root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
        echo "Error: not in a git repository"
        return 1
    }
    # --git-common-dir returns the .git directory, strip it
    repo_root="${repo_root%/.git}"

    local worktree_dir

    # If no branch specified, try to delete current worktree
    if [ -z "$branch" ]; then
        # Check if we're inside .worktrees/
        if [[ "$PWD" == "$repo_root/.worktrees/"* ]]; then
            # Extract the worktree name from the path
            local rel_path="${PWD#$repo_root/.worktrees/}"
            branch="${rel_path%%/*}"
            worktree_dir="$repo_root/.worktrees/$branch"
        else
            echo "Error: not inside a worktree (must be in .worktrees/ to delete current)"
            echo ""
            echo "Usage: wtd [branch-name]"
            echo ""
            echo "Existing worktrees:"
            git worktree list 2>/dev/null
            return 1
        fi
    else
        worktree_dir="$repo_root/.worktrees/$branch"
    fi

    if [ ! -d "$worktree_dir" ]; then
        echo "Error: worktree does not exist: $worktree_dir"
        return 1
    fi

    # If we're inside the worktree being deleted, cd to repo root first
    if [[ "$PWD" == "$worktree_dir"* ]]; then
        cd "$repo_root" || return 1
    fi

    # Try normal remove first, then force if needed (e.g., uncommitted changes)
    # If git doesn't recognize it as a worktree, clean up the directory manually
    if git worktree remove "$worktree_dir" 2>/dev/null; then
        echo "Worktree removed: $worktree_dir"
    elif git worktree remove --force "$worktree_dir" 2>/dev/null; then
        echo "Worktree removed (forced): $worktree_dir"
    else
        # Git doesn't recognize it as a worktree - could be orphaned directory
        # or worktree tracking got out of sync. Clean up manually.
        echo "Warning: git doesn't recognize this as a worktree, removing directory manually"
        rm -rf "$worktree_dir" && echo "Directory removed: $worktree_dir"
        # Also prune any stale worktree entries
        git worktree prune 2>/dev/null
    fi
}

# Helper to get main repo root (works from inside worktrees)
_wt_repo_root() {
    local repo_root
    repo_root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    echo "${repo_root%/.git}"
}

# Helper to get branch list for completion
_wt_branches() {
    local repo_root branches worktree_names
    repo_root="$(_wt_repo_root)" || return

    # Get all branches: local refs and remote refs (strip origin/ prefix), deduplicated
    branches=$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null | \
               sed 's#^origin/##' | \
               grep -v '^HEAD$' | \
               sort -u)

    # Also include existing worktree directory names (in case branch was deleted)
    if [ -d "$repo_root/.worktrees" ]; then
        worktree_names=$(ls -1 "$repo_root/.worktrees" 2>/dev/null)
        branches=$(printf '%s\n%s' "$branches" "$worktree_names" | sort -u)
    fi

    echo "$branches"
}

# Helper to get existing worktree names for wtd completion
_wtd_worktrees() {
    local repo_root
    repo_root="$(_wt_repo_root)" || return

    if [ -d "$repo_root/.worktrees" ]; then
        ls -1 "$repo_root/.worktrees" 2>/dev/null
    fi
}

# Shell-specific completion setup
if [ -n "$BASH_VERSION" ]; then
    # Bash completion for wt
    _wt_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -W "$(_wt_branches)" -- "$cur"))
    }
    complete -F _wt_completion wt

    # Bash completion for wtd
    _wtd_completion() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -W "$(_wtd_worktrees)" -- "$cur"))
    }
    complete -F _wtd_completion wtd
elif [ -n "$ZSH_VERSION" ]; then
    # Zsh completion for wt
    _wt_completion() {
        local branches
        branches=("${(@f)$(_wt_branches)}")
        _describe 'branch' branches
    }

    # Zsh completion for wtd
    _wtd_completion() {
        local worktrees
        worktrees=("${(@f)$(_wtd_worktrees)}")
        _describe 'worktree' worktrees
    }

    # compdef requires compinit to have been run first
    if (( $+functions[compdef] )); then
        compdef _wt_completion wt
        compdef _wtd_completion wtd
    fi
fi
