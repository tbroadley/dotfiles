#!/bin/bash

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

if ! echo "$command" | grep -qE '^git\s+push\b'; then
    exit 0
fi

upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || exit 0

diff_output=$(git diff "$upstream"...HEAD 2>/dev/null | grep '^+' | grep -v '^+++') || exit 0

if [ -z "$diff_output" ]; then
    exit 0
fi

prompt="Analyze this git diff for sensitive data that should not be pushed to a repository.

Look for:
- API keys, tokens, secrets (AWS, GitHub, Stripe, etc.)
- Passwords or credentials
- Private keys (SSH, PGP, etc.)
- Connection strings with embedded credentials
- .env file contents with real values
- High-entropy strings that look like secrets

<diff>
$diff_output
</diff>

Respond with ONLY a JSON object (no markdown, no explanation):
- If NO secrets found: {\"safe\": true}
- If secrets found: {\"safe\": false, \"findings\": [\"brief description of each finding\"]}"

scan_result=$(claude --print --model haiku --allowedTools '' --max-turns 1 -p "$prompt" 2>/dev/null) || exit 0

scan_result=$(echo "$scan_result" | sed 's/^```json//; s/^```//; /^$/d')

if echo "$scan_result" | grep -q '"safe":\s*true'; then
    exit 0
fi

if ! echo "$scan_result" | grep -q '"safe":\s*false'; then
    exit 0
fi

findings=$(echo "$scan_result" | jq -r '(.findings // [])[:5] | map("- " + .) | join("\n")' 2>/dev/null) || findings="Unable to parse findings"

jq -n --arg findings "$findings" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ("Potential secrets detected in commits:\n" + $findings + "\n\nReview and remove sensitive data before pushing.")
  }
}'
