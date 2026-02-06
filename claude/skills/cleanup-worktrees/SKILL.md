---
name: cleanup-worktrees
description: This skill should be used when the user asks to "clean up worktrees", "remove merged worktrees", "prune worktrees", or wants to delete git worktrees and branches for PRs that have been merged.
user-invocable: true
---

# Clean Up Merged Worktrees and Branches

Remove git worktrees and local branches whose PRs have been merged into the main branch.

## Workflow

### 1. List Worktrees

```bash
git worktree list
```

Identify all worktrees besides the main one. Extract the branch name for each.

### 2. Check PR Status via GitHub

For each worktree branch, check whether it has a **merged** PR on GitHub:

```bash
gh pr list --state merged --head "<branch-name>" --json number,title \
  --jq 'if length > 0 then .[0] | "#\(.number) \(.title)" else empty end'
```

**Do NOT use `git branch --merged main`** — this is unreliable for squash-merged PRs and also matches branches that simply haven't diverged from main yet (e.g., newly created branches with active local work).

Only branches with a confirmed merged PR on GitHub are candidates for removal.

### 3. Present Findings

Show the user a summary:
- Which worktrees have merged PRs (will be removed)
- Which have open PRs (will be kept)
- Which have no PR (will be kept)

Ask for confirmation before proceeding with removal.

### 4. Remove Worktrees and Branches

For each confirmed merged branch:

```bash
git worktree remove --force .worktrees/<worktree-dir>
git branch -D <branch-name>
```

Use `--force` for worktree removal since merged branches may have stale local changes (lock files, build artifacts, etc.) that are no longer relevant.

Use `git branch -D` (force delete) because squash-merged branches won't pass `git branch -d` validation — the local commits differ from the squashed merge commit on main.

### 5. Verify

```bash
git worktree list
```

Confirm only unmerged worktrees remain.

## Notes

- Never remove worktrees for branches with open PRs or no PR — these represent active work
- The `.worktrees/` directory convention uses branch names with `/` replaced by `-`
- Always confirm with the user before deleting if there are any surprises (e.g., significant uncommitted changes in a merged branch's worktree)
