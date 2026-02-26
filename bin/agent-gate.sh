# Agent gating system — source this file from shell rc
# If .allowed-agents exists in CWD or any parent, only listed agents may run.
# Usage: _check_agent_allowed <agent_name>

_check_agent_allowed() {
    local agent="$1"
    local dir="${2:-$PWD}"
    while true; do
        if [[ -f "$dir/.allowed-agents" ]]; then
            if grep -qx "$agent" "$dir/.allowed-agents"; then
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
