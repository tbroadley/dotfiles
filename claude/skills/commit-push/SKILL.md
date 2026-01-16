---
name: commit-push
description: This skill should be used when the user asks to "commit and push", "push my changes", or wants to commit, push, and respond to PR comments.
user-invocable: true
---

# Commit, Push, and Respond to PR Comments

Commit staged/unstaged changes, push to remote, and if on a PR, respond to and resolve any PR comment threads that were addressed by the pushed changes.

## Workflow

### 1. Commit and Push

Follow the standard git commit workflow:

1. Run `git status` and `git diff` to see changes
2. Run `git log --oneline -3` to match commit message style
3. Stage changes with `git add`
4. Create commit with descriptive message ending with:
   ```
   Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
   ```
5. Push to remote with `git push`

### 2. Check for Associated PR

Check if the current branch has an open PR:

```bash
gh pr view --json number,url,state 2>/dev/null
```

If no PR exists or PR is not open, stop here.

### 3. Get PR Review Comments

Fetch all review comments on the PR:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate
```

Also get the PR diff to understand what files/lines were changed:

```bash
gh pr diff
```

### 4. Identify Resolved Comments

For each unresolved comment thread, determine if the pushed changes address it by:
- Checking if the commented code was modified
- Checking if the feedback was implemented
- Checking if the issue raised was fixed

### 5. Respond and Resolve

For each comment that was addressed:

1. Leave a reply explaining what was done:
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

To get the thread ID for a comment, use:
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

- Only respond to comments that were actually addressed by the changes
- Do not resolve threads that were not addressed
- Prefix all GitHub comments with "Claude Code: "
- If unsure whether a comment was addressed, leave it unresolved
