---
name: upload-pr-images
description: Upload images to a GitHub PR description or comment using a shared gist as image hosting. Use when the user wants to add plots, screenshots, or other images to a PR.
user-invocable: true
---

# Upload Images to GitHub PRs via Gist

GitHub's API doesn't support direct image uploads to PR descriptions. This skill uses a shared gist as persistent image hosting.

## Shared Gist

Use the existing gist for all image uploads:
- **Gist ID:** `a7a894454779b8c3a27906f0e8d026fb`
- **Owner:** `tbroadley`
- **Clone URL:** `https://gist.github.com/a7a894454779b8c3a27906f0e8d026fb.git`

## Workflow

### 1. Clone or update the gist

```bash
GIST_ID="a7a894454779b8c3a27906f0e8d026fb"
GIST_DIR="/tmp/gist-images/${GIST_ID}"

if [ -d "$GIST_DIR" ]; then
  cd "$GIST_DIR" && git pull
else
  mkdir -p /tmp/gist-images
  gh gist clone "$GIST_ID" "$GIST_DIR"
  cd "$GIST_DIR"
fi
```

### 2. Copy images into the gist

Use descriptive filenames. If updating existing files, make them writable first (gist files from `gh gist clone` may be read-only):

```bash
chmod u+w "$GIST_DIR"/*.png 2>/dev/null
cp /path/to/image.png "$GIST_DIR/descriptive_name.png"
```

### 3. Commit and push

```bash
cd "$GIST_DIR"
git add -A
git commit -m "Add images for PR #<number>"
git push
```

### 4. Get the commit hash for cache-busting URLs

GitHub caches gist raw URLs aggressively. Pin URLs to a specific commit to ensure updated images are shown:

```bash
COMMIT=$(cd "$GIST_DIR" && git rev-parse HEAD)
```

### 5. Build raw URLs

```
https://gist.githubusercontent.com/tbroadley/a7a894454779b8c3a27906f0e8d026fb/raw/<COMMIT>/<filename>.png
```

### 6. Use in PR body or comment

```bash
BASE="https://gist.githubusercontent.com/tbroadley/${GIST_ID}/raw/${COMMIT}"

gh api repos/{owner}/{repo}/pulls/{number} -X PATCH -f body="$(cat <<EOF
## Plots

![Description](${BASE}/descriptive_name.png)
EOF
)"
```

Use `gh api` instead of `gh pr edit` to avoid "Projects (classic) deprecation" errors.

## Notes

- Always pin URLs to a **full** commit hash (`git rev-parse HEAD`). Short hashes (e.g., `4f295cd`) return 404 on `gist.githubusercontent.com`.
- Use `chmod u+w` before overwriting files — gist clones may have read-only permissions.
- Binary files (PNG, JPG) cannot be uploaded via `gh gist create` directly — the git clone/push approach is required.
- The gist accumulates files over time. This is fine; old files don't cost anything.
- **Bash `!` escaping**: Never build the PR body in a double-quoted bash variable — `!` in `![alt](url)` gets escaped to `\!` by bash history expansion, breaking image markdown. Always use a heredoc (`<<EOF`) to pass the body to `gh api`, as shown in step 6.
