#!/bin/bash

if [ -f "/.dockerenv" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Already running inside a dev container. Run commands directly here. Use /opt/python/bin/python3 instead of uv run for Python."
  }
}
EOF
elif [ -d ".devcontainer" ]; then
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
