#!/bin/bash
input=$(cat)

# Git info
R=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^https?://[^@]+@github\.com/##; s#^(https?://|git@)?github\.com[/:]##; s#\.git$##')
B=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
git_info="${R:-$(basename "$(pwd)")} ${B:-???}"

# Context usage
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
    printf '%s | ctx: %s%%' "$git_info" "$used"
else
    printf '%s' "$git_info"
fi
