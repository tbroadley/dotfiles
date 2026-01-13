#!/bin/bash

# SessionStart hook to detect dev container configuration
# Outputs additionalContext that gets injected into Claude's context

if [ -d ".devcontainer" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This repository has a .devcontainer/ directory. Build and start the dev container using the devcontainer CLI before running any commands. All commands should be executed inside the container, not on the host machine. Use /opt/python/bin/python3 instead of uv run for Python."
  }
}
EOF
else
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "No dev container configuration found. Run commands directly on the host."
  }
}
EOF
fi
