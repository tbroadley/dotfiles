#!/bin/bash
input=$(cat)

# Git info
R=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^https?://[^@]+@github\.com/##; s#^(https?://|git@)?github\.com[/:]##; s#\.git$##')
B=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
git_info="${R:-$(basename "$(pwd)")} ${B:-???}"

# Context usage
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
if [ -n "$used" ] && [ -n "$size" ]; then
    size_k=$((size / 1000))
    printf '%s | %.1f%%/%dk' "$git_info" "$used" "$size_k"
else
    printf '%s' "$git_info"
fi
