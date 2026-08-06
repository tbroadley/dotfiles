#!/bin/bash
# Scan outgoing commits for hardcoded secrets before `git push`.
#
# Fails CLOSED. Every step used to end in `|| exit 0`, so a missing jq, a
# branch with no upstream, an offline model or an unparseable reply all meant
# "push allowed, no scan, no message" — the failure mode you would never
# notice, on the one control standing between a committed secret and a public
# remote.
#
# Now anything that stops the scan from reaching a verdict returns `ask`: the
# push is not blocked, but it is put in front of a human who can say whether it
# was scanned. Only a positive finding returns `deny`, and only a clean scan
# returns silently.

set -uo pipefail

# `ask` rather than `deny` for "could not scan": the hook has not found a
# secret, it has failed to look. Blocking outright on a flaky model call would
# teach me to rip the hook out; surfacing it keeps the decision mine.
ask() {
    jq -n --arg reason "$1" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": ("Could not scan this push for secrets: " + $reason
          + "\n\nNothing was checked. Confirm only if you know what is in these commits.")
      }
    }' 2>/dev/null || printf '%s\n' "pre-push-secrets-scan: $1" >&2
    exit 0
}

deny() {
    jq -n --arg findings "$1" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("Potential secrets detected in commits:\n" + $findings
          + "\n\nReview and remove sensitive data before pushing.")
      }
    }'
    exit 0
}

input=$(cat)

# Without jq there is no reliable way to read the hook payload. Rather than wave
# through every Bash call in a broken environment, fall back to a raw look for a
# push and only then interrupt.
if ! command -v jq >/dev/null 2>&1; then
    if printf '%s' "$input" | grep -q 'git push'; then
        ask "jq is not installed on this machine, so the hook cannot read the command or diff"
    fi
    exit 0
fi

command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
    printf '%s' "$input" | grep -q 'git push' && ask "the hook input was not valid JSON"
    exit 0
}

# Not a push: nothing to do, and this is the overwhelmingly common path.
if ! printf '%s' "$command" | grep -qE '^git\s+push\b'; then
    exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    ask "this is not a git repository"
fi

# What to diff against. An upstream if there is one; otherwise the default
# branch, which is what makes a brand-new branch scannable — `git push -u` on a
# fresh branch has no upstream yet, and that used to skip the scan entirely on
# exactly the pushes most likely to be someone's first.
base=""
if upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) && [ -n "$upstream" ]; then
    base="$upstream"
elif default_ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) && [ -n "$default_ref" ]; then
    base="$default_ref"
elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    base="origin/master"
elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base="origin/main"
else
    ask "no upstream and no origin default branch, so there is nothing to diff against"
fi

# git diff runs on its own so its exit status is actually checkable; piping it
# straight into grep would hide a failure behind grep's status.
raw_diff=$(git diff "$base"...HEAD 2>/dev/null) || ask "git diff against $base failed"
diff_output=$(printf '%s\n' "$raw_diff" | grep '^+' | grep -v '^+++')

# A genuinely empty diff is a clean result, not a failure: there are no added
# lines, so there is nothing that could carry a secret.
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
- References to environment variables (e.g. \`process.env.API_KEY\`, \`\$LINEAR_API_KEY\`, \`os.getenv()\`)
- Code that reads secrets from config files, vaults, or env vars at runtime
- Variable names or keys that mention \"token\", \"secret\", \"key\", etc. without containing actual secret values
- Authorization headers that use variables/env vars for the token value
- Checksums, digests and commit SHAs, which are high-entropy but public

<diff>
$diff_output
</diff>

Respond with ONLY a JSON object (no markdown, no explanation):
- If NO hardcoded secrets found: {\"safe\": true}
- If hardcoded secrets found: {\"safe\": false, \"findings\": [\"brief description of each finding\"]}"

scan_result=$(claude --print --model haiku --allowedTools '' --max-turns 1 -p "$prompt" 2>/dev/null) \
    || ask "the scanner (claude --print) exited non-zero — offline, not logged in, or rate limited"

# shellcheck disable=SC2016  # `/^$/d` is sed's delete-empty-lines, not a shell variable
scan_result=$(printf '%s' "$scan_result" | sed 's/^```json//; s/^```//; /^$/d')

if [ -z "$scan_result" ]; then
    ask "the scanner returned nothing"
fi

if printf '%s' "$scan_result" | grep -q '"safe":[[:space:]]*true'; then
    exit 0
fi

if ! printf '%s' "$scan_result" | grep -q '"safe":[[:space:]]*false'; then
    ask "the scanner's reply did not contain a safe:true/false verdict"
fi

findings=$(printf '%s' "$scan_result" | jq -r '(.findings // [])[:5] | map("- " + .) | join("\n")' 2>/dev/null)
[ -n "$findings" ] || findings="- (the scanner reported secrets but its findings could not be parsed)"
deny "$findings"
