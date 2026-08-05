#!/usr/bin/env bash
# Tests for bin/with-secret, run against tests/fake-broker.py.
#
# The point of most of these is negative: that the value does not reach the
# caller's environment, the caller's output, or the disk, and that every way the
# broker can say no ends in a distinct exit code with an explanation rather than
# in the command running anyway.
#
#   ./tests/with-secret.test.sh

# The single-quoted `$DD_PAT` in the test commands below is deliberate: it must
# be expanded by the child, not by this shell.
# shellcheck disable=SC2016

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
with_secret="$here/../bin/with-secret"
fake_broker="$here/fake-broker.py"
secret="s3cret-value-abcdef"

tmp="$(mktemp -d)"
broker_pid=""
cleanup() {
    [ -n "$broker_pid" ] && kill "$broker_pid" 2>/dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT

passed=0
failed=0

ok() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
no() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

check_eq() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then ok "$name"; else no "$name" "want [$want], got [$got]"; fi
}
check_contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) ok "$name" ;;
        *) no "$name" "expected to find [$needle] in [$haystack]" ;;
    esac
}
check_lacks() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) no "$name" "did not expect to find [$needle] in [$haystack]" ;;
        *) ok "$name" ;;
    esac
}

# Start a broker with the given flags and point the environment at it.
start_broker() {
    [ -n "$broker_pid" ] && { kill "$broker_pid" 2>/dev/null; wait "$broker_pid" 2>/dev/null; }
    local portfile="$tmp/port"
    rm -f "$portfile"
    python3 "$fake_broker" --token "$broker_token" --value "$secret" "$@" > "$portfile" &
    broker_pid=$!
    for _ in $(seq 1 100); do
        [ -s "$portfile" ] && break
        sleep 0.05
    done
    [ -s "$portfile" ] || { echo "fake broker did not start" >&2; exit 1; }
    local port
    port="$(cat "$portfile")"
    export CREDENTIAL_BROKER_URL="http://127.0.0.1:$port"
}

# The token comes from a 0600 config file, the way it will on the box, so that
# "the child does not inherit the token" is a real check rather than an artifact
# of this script's own environment.
broker_token="test-token-0123456789"
conf="$tmp/broker.env"
printf 'CREDENTIAL_BROKER_TOKEN=%s\n' "$broker_token" > "$conf"
chmod 600 "$conf"
export CREDENTIAL_BROKER_CONFIG="$conf"
start_broker --record "$tmp/requests.jsonl"

# --- the happy path -----------------------------------------------------------

out="$("$with_secret" DD_PAT -- printenv DD_PAT 2>&1)"
check_eq "the child sees the value in its environment, redacted on the way out" \
    "<DD_PAT redacted>" "$out"
check_lacks "the value itself never reaches the caller's stdout" "$secret" "$out"

out="$("$with_secret" DD_PAT -- echo hello 2>&1)"
check_eq "ordinary output passes through untouched" "hello" "$out"

check_eq "the value is not in the caller's own environment afterwards" "" "${DD_PAT:-}"

out="$("$with_secret" DD_PAT -- printf '%s\n' 'Authorization: Bearer {{DD_PAT}}' 2>&1)"
check_eq "a {{FIELD}} placeholder in an argument is substituted, then redacted" \
    "Authorization: Bearer <DD_PAT redacted>" "$out"

out="$("$with_secret" DD_PAT --as DD_ACCESS_TOKEN -- printenv DD_ACCESS_TOKEN 2>&1)"
check_eq "--as puts the value in a differently named variable" "<DD_PAT redacted>" "$out"

out="$("$with_secret" DD_PAT --as DD_ACCESS_TOKEN -- printenv DD_PAT 2>&1)"; rc=$?
check_eq "--as means the field's own name is not set" "1" "$rc"
check_eq "--as leaves nothing behind under the field name" "" "$out"

out="$("$with_secret" DD_PAT --as DD_ACCESS_TOKEN -- printf '%s\n' 'Bearer {{DD_ACCESS_TOKEN}}' 2>&1)"
check_eq "--as renames the placeholder too" "Bearer <DD_PAT redacted>" "$out"

check_eq "the broker is told which variable it lands in" "DD_ACCESS_TOKEN" \
    "$(jq -r .request.env <<<"$(tail -1 "$tmp/requests.jsonl")")"

out="$("$with_secret" DD_PAT --as 'not a variable' -- echo hi 2>&1)"; rc=$?
check_eq "a junk --as name is a usage error" "64" "$rc"

out="$("$with_secret" DD_PAT -- printf '%s\n' 'no placeholder here' 2>&1)"
check_eq "arguments without a placeholder are passed through unchanged" "no placeholder here" "$out"

out="$("$with_secret" DD_PAT -- bash -c 'printf "%s\n" "$DD_PAT" >&2' 2>&1)"
check_eq "stderr is scrubbed too" "<DD_PAT redacted>" "$out"

out="$("$with_secret" DD_PAT -- bash -c 'printf "before %s after" "$DD_PAT"' 2>&1)"
check_eq "a final line with no newline is still scrubbed" "before <DD_PAT redacted> after" "$out"

"$with_secret" DD_PAT -- bash -c 'exit 7' >/dev/null 2>&1
check_eq "the command's exit status is what we exit with" "7" "$?"

out="$("$with_secret" DD_PAT -- bash -c 'printenv CREDENTIAL_BROKER_TOKEN' 2>&1)"
check_eq "the bearer token is not passed down to the child" "" "$out"

# The value must not survive anywhere on disk. Give the run its own TMPDIR and
# search it afterwards, including the exit-status file if it were left behind.
mkdir -p "$tmp/tmpdir"
TMPDIR="$tmp/tmpdir" "$with_secret" DD_PAT -- printenv DD_PAT >/dev/null 2>&1
if grep -rl "$secret" "$tmp/tmpdir" >/dev/null 2>&1; then
    no "nothing under TMPDIR contains the value" "found it in $tmp/tmpdir"
else
    ok "nothing under TMPDIR contains the value"
fi
check_eq "no leftover files under TMPDIR" "" "$(ls -A "$tmp/tmpdir")"

# --- what the broker is told --------------------------------------------------

recorded="$(tail -1 "$tmp/requests.jsonl")"
check_eq "the request names the field" "DD_PAT" "$(jq -r .request.field <<<"$recorded")"
check_eq "the request carries the full argv" "printenv DD_PAT" \
    "$(jq -r '.request.argv | join(" ")' <<<"$recorded")"
check_eq "the request carries the working directory" "$PWD" "$(jq -r .request.cwd <<<"$recorded")"
check_eq "the request carries the host" "$(hostname)" "$(jq -r .request.host <<<"$recorded")"
check_eq "the request authenticates with the bearer token" "Bearer $broker_token" \
    "$(jq -r .auth <<<"$recorded")"

"$with_secret" --reason "checking CPU on the runners" DD_PAT -- echo hi >/dev/null 2>&1
check_eq "a reason is passed through for the approval prompt" "checking CPU on the runners" \
    "$(jq -r .request.reason <<<"$(tail -1 "$tmp/requests.jsonl")")"

# --- refusals -----------------------------------------------------------------

start_broker --status 403 --error "curl is not on the allowlist for DD_PAT"
out="$("$with_secret" DD_PAT -- echo should-not-run 2>&1)"
rc=$?
check_eq "a refusal exits 3" "3" "$rc"
check_lacks "a refused command does not run" "should-not-run" "$out"
check_contains "a refusal repeats the broker's reason" "not on the allowlist" "$out"
check_contains "a refusal says the allowlist is not ours to edit" "cannot be
changed from this host" "$out"

start_broker --status 408 --error "nobody answered"
out="$("$with_secret" --timeout 5 DD_PAT -- echo should-not-run 2>&1)"
rc=$?
check_eq "an unanswered prompt exits 4" "4" "$rc"
check_contains "an unanswered prompt says not to retry in a loop" "do not retry" "$out"

start_broker --token "a-different-token-0123456789"  # not the one the box holds
out="$("$with_secret" DD_PAT -- echo should-not-run 2>&1)"
rc=$?
check_eq "a rejected bearer token exits 3" "3" "$rc"
check_lacks "a rejected bearer token does not run the command" "should-not-run" "$out"

start_broker --status 200 --value "short"
out="$("$with_secret" DD_PAT -- echo should-not-run 2>&1)"
rc=$?
check_eq "a value too short to scrub safely is refused" "3" "$rc"
check_lacks "a value too short to scrub safely does not run the command" "should-not-run" "$out"

# --- the laptop is not there --------------------------------------------------

kill "$broker_pid" 2>/dev/null; wait "$broker_pid" 2>/dev/null; broker_pid=""
out="$("$with_secret" DD_PAT -- echo should-not-run 2>&1)"
rc=$?
check_eq "an unreachable broker exits 2, like aws-sso-login" "2" "$rc"
check_contains "an unreachable broker blames the laptop, not the caller" "laptop is probably asleep" "$out"
check_contains "an unreachable broker says not to retry in a loop" "do not retry in a loop" "$out"
check_lacks "an unreachable broker does not run the command" "should-not-run" "$out"

# --- usage and configuration --------------------------------------------------

start_broker
out="$("$with_secret" DD_PAT echo hi 2>&1)"; rc=$?
check_eq "a missing -- is a usage error" "64" "$rc"
check_contains "a missing -- says so" "forget the --" "$out"

out="$("$with_secret" -- echo hi 2>&1)"; rc=$?
check_eq "no field is a usage error" "64" "$rc"

out="$("$with_secret" dd_pat -- echo hi 2>&1)"; rc=$?
check_eq "a lowercase field name is a usage error" "64" "$rc"

out="$("$with_secret" DD_PAT -- 2>&1)"; rc=$?
check_eq "no command is a usage error" "64" "$rc"

# Nobody should be woken up to approve a credential for a command that cannot run.
before="$(wc -l < "$tmp/requests.jsonl")"
out="$("$with_secret" DD_PAT -- definitely-not-installed --flag 2>&1)"; rc=$?
check_eq "a command that is not installed exits 127" "127" "$rc"
check_contains "a missing command says why nobody was asked" "no point asking" "$out"
check_eq "a missing command never reaches the broker" "$before" "$(wc -l < "$tmp/requests.jsonl")"

# A config file holding a bearer token has to be 0600. Everything above already
# read the token out of one; this checks the file is read for the URL too, and
# that a loose mode is refused rather than shrugged at.
conf2="$tmp/broker-full.env"
{
    printf 'CREDENTIAL_BROKER_URL=%s\n' "$CREDENTIAL_BROKER_URL"
    printf 'CREDENTIAL_BROKER_TOKEN=%s\n' "$broker_token"
} > "$conf2"
chmod 644 "$conf2"
out="$(CREDENTIAL_BROKER_CONFIG="$conf2" CREDENTIAL_BROKER_URL="" \
    "$with_secret" DD_PAT -- echo hi 2>&1)"; rc=$?
check_eq "a world-readable config is a configuration error" "78" "$rc"
check_contains "a world-readable config says how to fix it" "chmod 600" "$out"

chmod 600 "$conf2"
out="$(CREDENTIAL_BROKER_CONFIG="$conf2" CREDENTIAL_BROKER_URL="" \
    "$with_secret" DD_PAT -- echo from-config 2>&1)"; rc=$?
check_eq "a 0600 config file is read for the URL and token" "from-config" "$out"

out="$(CREDENTIAL_BROKER_CONFIG="$tmp/nonexistent.env" CREDENTIAL_BROKER_URL="" \
    CREDENTIAL_BROKER_HOST="" CREDENTIAL_BROKER_TOKEN="" "$with_secret" DD_PAT -- echo hi 2>&1)"; rc=$?
check_eq "no broker configured at all is a configuration error" "78" "$rc"
check_contains "no broker configured says what to write where" "CREDENTIAL_BROKER_HOST" "$out"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
