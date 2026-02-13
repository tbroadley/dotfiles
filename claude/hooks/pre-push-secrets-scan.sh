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

prompt="Analyze this git diff for hardcoded secrets that should not be pushed to a repository.

Look ONLY for actual secret values directly embedded in the code:
- Hardcoded API keys, tokens, or secrets (e.g. \`api_key = \"sk-abc123...\"\`)
- Hardcoded passwords or credentials
- Private key material (SSH, PGP, etc.)
- Connection strings with embedded passwords
- .env file contents with real secret values
- High-entropy strings that look like actual secret values

Do NOT flag:
- References to environment variables (e.g. \`process.env.API_KEY\`, \`\$TODOIST_TOKEN\`, \`os.getenv()\`)
- Code that reads secrets from config files, vaults, or env vars at runtime
- Variable names or keys that mention \"token\", \"secret\", \"key\", etc. without containing actual secret values
- Authorization headers that use variables/env vars for the token value

<diff>
$diff_output
</diff>

Respond with ONLY a JSON object (no markdown, no explanation):
- If NO hardcoded secrets found: {\"safe\": true}
- If hardcoded secrets found: {\"safe\": false, \"findings\": [\"brief description of each finding\"]}"

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
