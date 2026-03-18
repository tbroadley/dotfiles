#!/bin/bash
input=$(cat)

# Git info
R=$(git config --get remote.origin.url 2>/dev/null | sed -E 's#^https?://[^@]+@github\.com/##; s#^(https?://|git@)?github\.com[/:]##; s#\.git$##')
B=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
git_info="${R:-$(basename "$(pwd)")} ${B:-???}"

# Context usage
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

# Cost
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

output="$git_info"

if [ -n "$cost" ]; then
    output=$(printf '%s | $%.2f' "$output" "$cost")
fi

if [ -n "$used" ] && [ -n "$size" ]; then
    if [ "$size" -ge 1000000 ]; then
        size_label="$(awk "BEGIN{printf \"%.0f\", $size/1000000}")M"
    else
        size_label="$((size / 1000))k"
    fi
    output=$(printf '%s | %.1f%%/%s' "$output" "$used" "$size_label")
fi

printf '%s' "$output"
