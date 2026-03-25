# Agent gating system — source this file from shell rc
# If .allowed-agents exists in CWD or any parent, only listed agents may run.
#
# Syntax:
#   agent_name          — allow the agent with no restrictions
#   agent_name[glob]    — allow the agent, restrict models to glob pattern
#   agent_name[g1,g2]   — allow the agent, restrict models to multiple globs
#
# Examples:
#   pi                  — allow pi with all models
#   pi[claude*]         — allow pi, only claude models
#   pi[claude*,gpt-4*]  — allow pi, only claude and gpt-4 models
#
# Usage: _check_agent_allowed <agent_name>
#        _get_agent_model_filters <agent_name> [dir]

_check_agent_allowed() {
    local agent="$1"
    local dir="${2:-$PWD}"
    while true; do
        if [[ -f "$dir/.allowed-agents" ]]; then
            # Match "agent" or "agent[...]"
            if grep -qE "^${agent}(\[.*\])?$" "$dir/.allowed-agents"; then
                return 0
            fi
            echo "agent-gate: '$agent' is not allowed here (per $dir/.allowed-agents)" >&2
            return 1
        fi
        [[ "$dir" == "/" ]] && break
        dir="$(dirname "$dir")"
    done
    return 0
}

# Print comma-separated model filter globs for an agent, or empty if unrestricted.
# Walks up from dir (default $PWD) looking for .allowed-agents.
_get_agent_model_filters() {
    local agent="$1"
    local dir="${2:-$PWD}"
    while true; do
        if [[ -f "$dir/.allowed-agents" ]]; then
            local line
            line="$(grep -E "^${agent}\[.*\]$" "$dir/.allowed-agents" | head -1)"
            if [[ -n "$line" ]]; then
                # Extract content between [ and ]
                local filters="${line#*[}"
                filters="${filters%]}"
                echo "$filters"
            fi
            return 0
        fi
        [[ "$dir" == "/" ]] && break
        dir="$(dirname "$dir")"
    done
    return 0
}
