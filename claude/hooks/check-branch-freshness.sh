#!/bin/bash

# SessionStart hook: warn if current branch is behind its remote tracking branch.

# Not a git repo — nothing to check.
git rev-parse --git-dir &>/dev/null || exit 0

# Fetch latest remote refs.
git fetch --quiet 2>/dev/null

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# No upstream tracking branch — nothing to compare against.
git rev-parse --verify "@{u}" &>/dev/null || exit 0

behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null)

if [ "$behind" -gt 0 ]; then
  upstream=$(git rev-parse --abbrev-ref "@{u}" 2>/dev/null)
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "WARNING: Branch '$branch' is $behind commit(s) behind '$upstream'. Run 'git pull --rebase' or 'git pull --ff-only' before making any code changes to avoid working on stale code."
  }
}
EOF
fi
