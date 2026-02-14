---
name: daily-activity
description: Summarize daily GitHub activity including PRs and direct commits with line counts. Use when the user asks "what did I do today", "daily summary", "my GitHub activity", or similar.
user-invocable: true
---

# Daily GitHub Activity Summary

Summarize the user's GitHub activity for today (or a specified date), including pull requests and direct commits with line change counts.

## Configuration

**GitHub Username:** tbroadley

**Timezone:** PST (UTC-8)

## Workflow

### 1. Determine Date Range

By default, summarize today's activity. The user may specify a different date.

Convert the target date to UTC range for GitHub API queries:
- PST date X = UTC date X 08:00:00 to UTC date X+1 07:59:59

```bash
# For today in PST
# PST is UTC-8, so "today" in PST started at 08:00 UTC
START_UTC=$(TZ=America/Los_Angeles date -v0H -v0M -v0S -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "today 00:00 PST" -u +%Y-%m-%dT%H:%M:%SZ)
END_UTC=$(TZ=America/Los_Angeles date -v+1d -v0H -v0M -v0S -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "tomorrow 00:00 PST" -u +%Y-%m-%dT%H:%M:%SZ)
```

### 2. Find Pull Requests

Search for PRs authored by the user that were updated within the date range:

```bash
gh search prs --author=tbroadley --updated=">=$TARGET_DATE" --json number,title,repository,createdAt,updatedAt --limit 50
```

For each PR found:
1. Check if it was created today OR had commits pushed today
2. Filter commits by date to identify which were pushed today
3. Get line change stats

**IMPORTANT:** Always use `gh api` to list PR commits—never use `gh pr view --json commits`. The `--json commits` output can show rebased timestamps (e.g., all commits dated identically) instead of actual author dates, causing today's commits to be missed entirely.

**For PRs created today:** Report the total PR additions/deletions.

**For PRs created earlier but with commits today:** Calculate line changes only for today's commits:
```bash
gh api repos/<owner>/<repo>/pulls/<number>/commits --paginate --jq '.[] | select(.commit.author.date >= "START_UTC" and .commit.author.date < "END_UTC") | .sha'
```

Then for each commit SHA:
```bash
gh api "repos/<owner>/<repo>/commits/<sha>" --jq '{additions: .stats.additions, deletions: .stats.deletions}'
```

### 3. Find Direct Commits to Main

Find commits by the user that were pushed directly to the default branch (not via PR).

**Step 1: Search for recent commits by the user across all of GitHub:**

```bash
gh search commits --author=tbroadley --author-date=">=$TARGET_DATE" --json repository,sha,commit --limit 100
```

**Step 2: For each commit, check if it's on the default branch and not from a PR:**

```bash
# Get the repo's default branch
DEFAULT_BRANCH=$(gh api "repos/<owner>/<repo>" --jq '.default_branch')

# Check if commit is on the default branch
gh api "repos/<owner>/<repo>/commits/$DEFAULT_BRANCH" --jq '.sha' | grep -q "^${COMMIT_SHA:0:7}" && echo "on default branch"

# Or check branches containing this commit
gh api "repos/<owner>/<repo>/commits/<sha>/branches-where-head" --jq '.[].name' | grep -q "^$DEFAULT_BRANCH$"
```

**Step 3: Check if commit came from a merged PR (exclude these):**

```bash
# Search for PRs that contain this commit
gh api "repos/<owner>/<repo>/commits/<sha>/pulls" --jq 'length'
# If length > 0, this commit was part of a PR - exclude it
```

**Step 4: For qualifying direct commits, get line stats:**

```bash
gh api "repos/<owner>/<repo>/commits/<sha>" --jq '{additions: .stats.additions, deletions: .stats.deletions}'
```

Group results by repository for the summary.

### 4. Generate Summary

Present the results in a structured format:

**Pull Requests:**
| PR | Repository | Title | +/- |
|----|------------|-------|-----|
| #N | org/repo | Title | +X/-Y |

Note: For PRs spanning multiple days, indicate whether the +/- is for today's commits only or the total PR.

**Direct Commits to Main (by Repo):**
| Repo | Commits | +/- |
|------|---------|-----|
| owner/repo | N | +X/-Y |

Optionally list individual commits with their messages.

**Totals:**
- Total PRs with activity: N
- Total direct commits: N
- Total lines changed: +X/-Y

### 5. Optional: Summarize Changes

If the user asks for a summary of what the changes did (not just line counts), provide a brief description of each PR and group of commits based on their titles/messages.

## Notes

- Use `gh` CLI for all GitHub operations (not WebFetch)
- Handle pagination for repos/PRs with many commits
- Large line counts on older PRs may indicate rebases/merges - note this in the output
- If a repo doesn't exist or user doesn't have access, skip it gracefully
