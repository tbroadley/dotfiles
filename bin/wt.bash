# wt - create or enter git worktree
# Usage: wt <branch-name>
#
# If a worktree for the branch already exists, cd into it.
# Otherwise, create the worktree with proper setup (.env, DVC cache) and cd into it.
#
# Supports bash and zsh with tab completion for branch names.

wt() {
    local branch="$1"
    if [ -z "$branch" ]; then
        echo "Usage: wt <branch-name>"
        echo ""
        echo "Existing worktrees:"
        git worktree list 2>/dev/null || echo "  (not in a git repository)"
        return 1
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "Error: not in a git repository"
        return 1
    }

    local worktree_dir="$repo_root/.worktrees/$branch"

    # If worktree already exists in .worktrees/, cd into it
    if [ -d "$worktree_dir" ]; then
        cd "$worktree_dir"
        return 0
    fi

    # Check if branch is already checked out in another worktree (e.g., main in repo root)
    local existing_worktree
    existing_worktree=$(git worktree list --porcelain 2>/dev/null | \
        awk -v branch="refs/heads/$branch" '/^worktree /{path=$2} /^branch /{if ($2 == branch) print path}')
    if [ -n "$existing_worktree" ]; then
        cd "$existing_worktree"
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

    echo "Worktree created: $worktree_dir"
    cd "$worktree_dir"
}

# wtd - delete a git worktree
# Usage: wtd <branch-name>
wtd() {
    local branch="$1"
    if [ -z "$branch" ]; then
        echo "Usage: wtd <branch-name>"
        echo ""
        echo "Existing worktrees:"
        git worktree list 2>/dev/null || echo "  (not in a git repository)"
        return 1
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "Error: not in a git repository"
        return 1
    }

    local worktree_dir="$repo_root/.worktrees/$branch"

    if [ ! -d "$worktree_dir" ]; then
        echo "Error: worktree does not exist: $worktree_dir"
        return 1
    fi

    # If we're inside the worktree being deleted, cd to repo root first
    if [[ "$PWD" == "$worktree_dir"* ]]; then
        cd "$repo_root"
    fi

    git worktree remove "$worktree_dir" && echo "Worktree removed: $worktree_dir"
}

# Helper to get branch list for completion
_wt_branches() {
    local repo_root branches worktree_names
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return

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
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return

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
