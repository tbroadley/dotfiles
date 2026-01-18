# Rebase Stacked Diff After Base Merges

Use this skill when a branch was based on another feature branch (stacked diff), and that base branch has now been merged to main. The current branch needs to be rebased onto main, skipping commits that were already merged.

## When to Use

- Branch B was created from Branch A (not main)
- Branch A has been merged to main
- Branch B now shows as "diverged" from its remote
- PR for Branch B shows merge conflicts or "CONFLICTING" status
- `git log` shows commits from Branch A in Branch B's history

## Workflow

### 1. Verify the Situation

```bash
# Check current branch status
git status

# See how the branch relates to main
git log --oneline --graph HEAD~20..HEAD

# Check if the PR is in a conflicting state
gh pr view --json mergeable,mergeStateStatus
```

If you see `"mergeStateStatus": "DIRTY"` or `"mergeable": "CONFLICTING"`, proceed.

### 2. Fetch Latest and Start Rebase

```bash
git fetch origin main

# Start interactive rebase onto main
git rebase origin/main
```

### 3. Handle Already-Merged Commits

When git tries to apply commits that are already in main (via the merged base branch), you'll see conflicts. These commits should be **skipped**, not resolved.

**Signs a commit should be skipped:**
- The commit message matches one from the merged PR
- Git shows "patch contents already upstream"
- Conflicts are in files that were part of the base branch's changes

**For each conflicting commit that was already merged:**

```bash
git rebase --skip
```

**Git will automatically drop some commits** with messages like:
```
dropping abc123 Some commit message -- patch contents already upstream
```

This is expected and correct.

### 4. Resolve Genuine Conflicts

If you encounter a conflict in code that is genuinely new to this branch:

1. Check if the conflict is from your branch's unique changes
2. Resolve the conflict manually
3. Stage the resolution: `git add <files>`
4. Continue: `git rebase --continue`

### 5. Force Push the Rebased Branch

After the rebase completes:

```bash
git push --force-with-lease origin <branch-name>
```

Use `--force-with-lease` (not `--force`) for safety.

### 6. Verify PR Status

```bash
gh pr view --json mergeable,mergeStateStatus
gh pr checks
```

The PR should now show:
- `"mergeable": "MERGEABLE"`
- `"mergeStateStatus": "BLOCKED"` (waiting for CI) or `"CLEAN"` (ready to merge)

## Example Session

```
$ git rebase origin/main
Rebasing (1/15)
CONFLICT (content): Merge conflict in src/feature.py
error: could not apply abc123... Add feature from base branch

# This commit was part of the base branch - skip it
$ git rebase --skip

Rebasing (2/15)
dropping def456 Another base branch commit -- patch contents already upstream
Rebasing (3/15)
...
Successfully rebased and updated refs/heads/my-branch.

$ git push --force-with-lease origin my-branch
```

## Troubleshooting

### "Would make commit empty"
The commit's changes are already in main. Skip it:
```bash
git rebase --skip
```

### Accidentally resolved instead of skipping
If you resolved a conflict that should have been skipped:
```bash
git rebase --abort
# Start over
git rebase origin/main
```

### Not sure if commit should be skipped
Check if the commit exists in main:
```bash
# Get the commit message from the conflict
git log --oneline -1 REBASE_HEAD

# Search for similar commits in main
git log --oneline origin/main | grep "<keywords from commit>"
```

### Too many commits to skip manually
If there are many commits from the base branch, consider:
```bash
# Find where your branch diverged from the base branch
git merge-base HEAD origin/main

# Interactive rebase to select only your commits
git rebase -i origin/main
# In the editor, delete lines for commits that came from the base branch
```

## Notes

- Always verify which commits are yours vs from the base branch before rebasing
- The number of commits after rebase should be fewer than before (base branch commits removed)
- CI should pass after rebasing if it passed before the base branch merged
