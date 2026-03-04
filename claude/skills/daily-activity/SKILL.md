---
name: daily-activity
description: Summarize daily GitHub activity including PRs and direct commits with line counts. Use when the user asks "what did I do today", "daily summary", "my GitHub activity", or similar.
user-invocable: true
---

# Daily GitHub Activity Summary

Summarize the user's GitHub activity for today (or a specified date), including pull requests and non-PR commits (both default-branch and branch-only) with line change counts.

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

**IMPORTANT:** Always use `gh api` to list PR commits, never `gh pr view --json commits`. The `--json commits` output can show rebased timestamps (e.g., all commits dated identically) instead of actual author dates, causing today's commits to be missed.

**For PRs created today:** Report the total PR additions/deletions.

**For PRs created earlier but with commits today:** Calculate line changes only for today's commits:
```bash
gh api repos/<owner>/<repo>/pulls/<number>/commits --paginate --jq '.[] | select(.commit.author.date >= "START_UTC" and .commit.author.date < "END_UTC") | .sha'
```

Then for each commit SHA:
```bash
gh api "repos/<owner>/<repo>/commits/<sha>" --jq '{additions: .stats.additions, deletions: .stats.deletions}'
```

### 3. Find Non-PR Commits (Default Branch + Branch-Only)

Find commits authored by the user in the date window that are not part of any PR, then split into:
- direct commits on default branch
- commits on non-default branches (branch-only work)

**Step 1: Build candidate repos and commits**

Use recent commit search to find repos with user activity:
```bash
gh search commits --author=tbroadley --author-date=">=$TARGET_DATE" --json repository,sha,commit --limit 200
```

Collect unique repos from this output and from PR activity in step 2.

**Step 2: For each repo, enumerate branches and fetch commits in window**

```bash
# List branches (paginate)
gh api "repos/<owner>/<repo>/branches?per_page=100&page=1"

# Fetch commits for a specific branch in date window
# IMPORTANT: Use -X GET with -f for sha/since/until so branch names are URL-encoded safely (e.g., names containing '#').
gh api -X GET "repos/<owner>/<repo>/commits" \
  -f "sha=<branch_name>" \
  -f "since=$START_UTC" \
  -f "until=$END_UTC" \
  -f "per_page=100"
```

Deduplicate by commit SHA across branches.

**Step 3: Keep only the user's commits**

Accept a commit if login or email matches the user:
- `author.login == tbroadley` or `committer.login == tbroadley`
- or author/committer email matches the user's known email

**Step 4: Exclude commits that belong to a PR**

```bash
gh api "repos/<owner>/<repo>/commits/<sha>/pulls" --jq 'length'
# If length > 0, commit is associated with a PR; exclude from non-PR buckets.
```

**Step 5: Split non-PR commits into default-branch vs branch-only**

```bash
# Default branch name
DEFAULT_BRANCH=$(gh api "repos/<owner>/<repo>" --jq '.default_branch')

# Commits on default branch in date window
gh api -X GET "repos/<owner>/<repo>/commits" \
  -f "sha=$DEFAULT_BRANCH" \
  -f "since=$START_UTC" \
  -f "until=$END_UTC" \
  -f "per_page=100"
```

If non-PR commit SHA appears in the default-branch commit set, classify as direct-to-default. Otherwise classify as branch-only.

**Step 6: Get line stats for each included commit**

```bash
gh api "repos/<owner>/<repo>/commits/<sha>" --jq '{additions: .stats.additions, deletions: .stats.deletions}'
```

Group results by repository for summary tables.

### 4. Generate Summary

Present results in structured format:

**Pull Requests:**
| PR | Repository | Title | +/- |
|----|------------|-------|-----|
| #N | org/repo | Title | +X/-Y |

Note: For PRs spanning multiple days, indicate whether +/- is today's commits only or total PR.

**Direct Commits to Default Branch (non-PR):**
| Repo | Commits | +/- |
|------|---------|-----|
| owner/repo | N | +X/-Y |

**Branch-Only Commits (non-PR):**
| Repo | Branches | Commits | +/- |
|------|----------|---------|-----|
| owner/repo | branch-a, branch-b | N | +X/-Y |

Optionally list individual commits with messages.

**Totals:**
- Total PRs with activity: N
- Total non-PR default-branch commits: N
- Total non-PR branch-only commits: N
- Total lines changed: +X/-Y

### 5. Optional: Summarize Changes

If the user asks for what the changes did (not just line counts), provide a brief description of each PR and non-PR commit group based on titles/messages.

## Notes

- Use `gh` CLI for all GitHub operations (not WebFetch)
- Handle pagination for repos/PRs with many commits
- Large line counts on older PRs may indicate rebases/merges; call this out
- If a repo is inaccessible, skip it and note that it was skipped
