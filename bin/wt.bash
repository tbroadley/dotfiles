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

# Repair a worktree's .git file and the main repo's gitdir pointer when
# absolute paths are stale (e.g., repo was created on host but accessed in a
# dev container at a different mount point).
_wt_repair_worktree() {
    local worktree_dir="$1"
    local repo_git_dir="$2"  # e.g., /home/user/app/.git

    local git_file="$worktree_dir/.git"
    [ -f "$git_file" ] || return 1

    # Read current gitdir pointer from the worktree's .git file
    local current_gitdir
    current_gitdir="$(cat "$git_file" 2>/dev/null)" || return 1
    current_gitdir="${current_gitdir#gitdir: }"

    # Extract the worktree name from the path (last component of gitdir path)
    local wt_name="${current_gitdir##*/}"
    [ -n "$wt_name" ] || return 1

    local correct_gitdir="$repo_git_dir/worktrees/$wt_name"

    # Fix the worktree's .git file if the path is wrong
    if [ "$current_gitdir" != "$correct_gitdir" ]; then
        echo "gitdir: $correct_gitdir" > "$git_file"
    fi

    # Fix the main repo's gitdir file pointing back to the worktree
    local repo_gitdir_file="$repo_git_dir/worktrees/$wt_name/gitdir"
    if [ -f "$repo_gitdir_file" ]; then
        local current_back_ref
        current_back_ref="$(cat "$repo_gitdir_file" 2>/dev/null)"
        local correct_back_ref="$worktree_dir/.git"
        if [ "$current_back_ref" != "$correct_back_ref" ]; then
            echo "$correct_back_ref" > "$repo_gitdir_file"
        fi
    fi
}

# Find the main repo root, even from inside a broken worktree.
# Falls back to directory traversal when git rev-parse fails.
_wt_find_repo_root() {
    # Try git first (works when git paths are valid)
    local repo_root
    if repo_root="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -d "$repo_root" ]; then
        echo "${repo_root%/.git}"
        return 0
    fi

    # Fallback: walk up from PWD looking for a directory with both .git/ and .worktrees/
    # This handles the case where we're inside a broken worktree whose .git file
    # points to a stale host path
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] && [ -d "$dir/.worktrees" ]; then
            echo "$dir"
            return 0
        fi
        dir="${dir%/*}"
        [ -z "$dir" ] && dir="/"
    done

    return 1
}

wt() {
    local branch="$1"

    # Get the main repo root (not worktree root)
    local repo_root
    repo_root="$(_wt_find_repo_root)" || {
        echo "Error: not in a git repository"
        return 1
    }

    # If git rev-parse failed but we found repo root by directory traversal,
    # we're likely in a broken worktree—repair it so git commands work
    if ! git rev-parse --git-common-dir &>/dev/null; then
        if [ -d "$repo_root/.git" ]; then
            _wt_repair_worktree "$PWD" "$repo_root/.git"
        fi
    fi

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

    # Replace forward slashes with dashes for directory name (e.g., user/feature -> user-feature)
    local dir_name="${branch//\//-}"
    local worktree_dir="$repo_root/.worktrees/$dir_name"

    # If worktree already exists in .worktrees/, cd into it
    if [ -d "$worktree_dir" ]; then
        # Repair stale gitdir paths (e.g., created on host, accessed in container)
        if [ -d "$repo_root/.git" ]; then
            _wt_repair_worktree "$worktree_dir" "$repo_root/.git"
        fi
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

# wtd - delete a git worktree and its backing branch
# Usage: wtd [branch-name]
#
# wtd          - delete the current worktree (if inside .worktrees/)
# wtd <branch> - delete the worktree for <branch>
#
# Also deletes the local branch that was backing the worktree.
wtd() {
    local branch="$1"

    # Get the main repo root (not worktree root)
    local repo_root
    repo_root="$(_wt_find_repo_root)" || {
        echo "Error: not in a git repository"
        return 1
    }

    # Repair current worktree if git paths are broken
    if ! git rev-parse --git-common-dir &>/dev/null; then
        if [ -d "$repo_root/.git" ]; then
            _wt_repair_worktree "$PWD" "$repo_root/.git"
        fi
    fi

    local worktree_dir
    local branch_to_delete

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
        # Replace forward slashes with dashes for directory name (e.g., user/feature -> user-feature)
        local dir_name="${branch//\//-}"
        worktree_dir="$repo_root/.worktrees/$dir_name"
    fi

    if [ ! -d "$worktree_dir" ]; then
        echo "Error: worktree does not exist: $worktree_dir"
        return 1
    fi

    # Get the branch name from the worktree before deleting it
    # The worktree list --porcelain output has: worktree <path>\nHEAD <sha>\nbranch <ref>
    branch_to_delete=$(git worktree list --porcelain 2>/dev/null | \
        awk -v wt="$worktree_dir" '/^worktree /{path=$2} /^branch /{if (path == wt) {sub(/^refs\/heads\//, "", $2); print $2}}')

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

    # Delete the backing branch if we found one and it's not a protected branch
    if [ -n "$branch_to_delete" ] && [ "$branch_to_delete" != "main" ] && [ "$branch_to_delete" != "master" ]; then
        if git branch -d "$branch_to_delete" 2>/dev/null; then
            echo "Branch deleted: $branch_to_delete"
        elif git branch -D "$branch_to_delete" 2>/dev/null; then
            echo "Branch deleted (forced): $branch_to_delete"
        fi
    fi
}

# Helper to get main repo root (works from inside worktrees)
_wt_repo_root() {
    _wt_find_repo_root
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
