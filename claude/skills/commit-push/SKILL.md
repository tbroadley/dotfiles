---
name: commit-push
description: This skill should be used when the user asks to "commit and push", "push my changes", or wants to commit, push, and respond to PR comments.
user-invocable: true
---

# Commit, Push, and Ensure CI Passes

Commit changes, run local validation, push to remote, open a draft PR if needed, and ensure CI passes.

## Workflow

### 1. Run Local Validation

Before committing, run all local checks:

**Linting, Typechecking, and Formatting:**
- Run the project's linter (e.g., `ruff check`, `eslint`, `golangci-lint`)
- Run the typechecker (e.g., `pyright`, `mypy`, `tsc --noEmit`)
- Run the formatter (e.g., `ruff format --check`, `prettier --check`, `gofmt`)
- Fix any issues found before proceeding

**Tests:**
- Check if the project has slow tests marked with `@pytest.mark.slow` (search for `mark.slow` in test files)
- If slow tests exist: run `pytest -m "not slow"` for fast tests, then run affected slow tests
- If no slow test markers exist, run all tests: `pytest`, `npm test`, `go test ./...`
- To identify affected slow tests, check which test files import or exercise modified code
- If pytest-xdist is available (`uv pip show pytest-xdist`), use `-n auto` for parallel execution:
  ```bash
  pytest -n auto -m "not slow"  # fast tests in parallel
  pytest -n auto path/to/slow_test1.py path/to/slow_test2.py  # affected slow tests in parallel
  ```

### 2. DVC (Data Version Control)

If this is a DVC-tracked repository (has `.dvc` files or `dvc.yaml`):
- Run `dvc repro` to reproduce any affected pipelines
- Run `dvc push` to push data artifacts to remote storage
- This prevents `check-dvc` CI failures

### 3. Commit and Push

Once local validation passes:

1. Run `git status` and `git diff` to see changes
2. Run `git log --oneline -3` to match commit message style
3. Stage changes with `git add`
4. Create commit with descriptive message ending with:
   ```
   Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
   ```
5. Push to remote with `git push`

### 4. Determine PR Base Branch

Before creating a PR, determine the correct base branch:

```bash
# Get the main/master branch name
main_branch=$(git remote show origin | grep 'HEAD branch' | cut -d: -f2 | xargs)

# Find the merge-base with main
merge_base=$(git merge-base HEAD origin/$main_branch)

# Check if there's another branch between current branch and main
# This finds branches that contain the merge-base but are not main
intermediate_branch=$(git branch -r --contains $merge_base | grep -v "origin/$main_branch" | grep -v "origin/HEAD" | head -1 | xargs)

# If an intermediate branch exists and is an ancestor of HEAD, use it as base
if [ -n "$intermediate_branch" ]; then
  base_branch=${intermediate_branch#origin/}
else
  base_branch=$main_branch
fi
```

Use `$base_branch` as the PR base instead of always using main/master.

### 5. Open or Update Draft PR

Check if the current branch has an open PR:

```bash
gh pr view --json number,url,state,isDraft 2>/dev/null
```

**If no PR exists:**
- Create a draft PR targeting the correct base branch:
  ```bash
  gh pr create --draft --base $base_branch --title "..." --body "..."
  ```

**If PR exists but is not a draft:**
- Continue with the existing PR

### 6. Wait for CI and Ensure It Passes

After pushing, monitor CI status:

```bash
gh pr checks --watch
```

**If CI cannot run (e.g., merge conflict):**
1. Identify the blocker: `gh pr view --json mergeable,mergeStateStatus`
2. If merge conflict:
   ```bash
   git fetch origin $base_branch
   git rebase origin/$base_branch
   # Resolve conflicts
   git add .
   git rebase --continue
   ```
3. Run local validation again (step 1)
4. Force push: `git push --force-with-lease`
5. Wait for CI again

**If CI fails:**
1. Check which jobs failed: `gh pr checks`
2. Get failure details: `gh run view <run_id> --log-failed`
3. Fix the failing tests/checks locally
4. Run local validation again (step 1)
5. Commit the fixes and push
6. Repeat until CI passes

### 7. Respond to PR Comments (if applicable)

If there are existing PR review comments, check if pushed changes address them.

Fetch review comments:
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate
```

For each unresolved comment that was addressed:

1. Leave a reply:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies \
     -f body="Claude Code: <explanation of how this was addressed>"
   ```

2. Resolve the thread:
   ```bash
   gh api graphql -f query='
     mutation {
       resolveReviewThread(input: {threadId: "<thread_id>"}) {
         thread { isResolved }
       }
     }
   '
   ```

To get thread IDs:
```bash
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                id
                databaseId
                body
              }
            }
          }
        }
      }
    }
  }
'
```

## Notes

- Always run local validation before pushing to catch issues early
- Only respond to PR comments that were actually addressed by the changes
- Prefix all GitHub comments with "Claude Code: "
- If CI keeps failing after multiple attempts, report the issue to the user
- The goal is a green CI on a draft PR before considering the task complete
