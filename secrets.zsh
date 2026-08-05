# Vault-backed credentials for the shell.
#
# No secrets live on disk. Values come from a single Bitwarden item, fetched on
# demand: fetching at shell startup would add 1-2s to every new terminal, so
# nothing is fetched until a command that needs credentials actually runs.
#
# Sourced from .zshrc. Machine-specific, non-secret config (DD_SITE, OAuth client
# ids, and so on) belongs in ~/.zshrc.local, which is deliberately untracked.

# Name of the Bitwarden item holding the credential fields.
: "${METR_SECRETS_ITEM:=METR shell env}"

# Commands that cannot work without vault credentials. Each is wrapped so it
# FAILS FAST rather than running on with the variables unset and dying in some
# confusing downstream way.
#
# Extend from ~/.zshrc.local, before the first prompt:
#     METR_SECRET_COMMANDS+=(my-tool)
#
# Do NOT add commands that have their own auth (hawk, gws — both OIDC), or that
# work fine without these variables (claude). And never add a name that collides
# with a real system command: `dd` is coreutils dd, not Datadog.
typeset -ga METR_SECRET_COMMANDS
METR_SECRET_COMMANDS=(linear datadog airtable golinks status-dashboard)

# Unlock the vault for THIS shell only. BW_SESSION is deliberately never written
# to disk.
bwunlock() {
  local s
  s="$(bw unlock --raw)" || return 1
  export BW_SESSION="$s"
  echo "Vault unlocked for this shell."
}

# Pull every credential field into the environment. Idempotent and cheap after
# the first call. One decrypt for all fields rather than one per variable.
secrets-load() {
  [[ -n "$_METR_SECRETS_LOADED" && -z "$1" ]] && return 0

  if ! command -v bw >/dev/null 2>&1; then
    print -u2 "secrets-load: bw not installed"
    return 1
  fi

  if [[ "$(bw status 2>/dev/null | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p')" != "unlocked" ]]; then
    print -u2 -P "%F{yellow}secrets-load: Bitwarden vault is locked.%f Run %B'bwunlock'%b, then re-run this command."
    return 1
  fi

  local json
  json="$(bw get item "$METR_SECRETS_ITEM" 2>/dev/null)" || {
    print -u2 "secrets-load: could not read item '$METR_SECRETS_ITEM'"
    return 1
  }

  local kv
  # One `export NAME=value` per custom field, quoted safely by jq's @sh.
  kv="$(printf '%s' "$json" | jq -r '
    .fields[]?
    | select(.name != null and .value != null)
    | "export \(.name)=\(.value | @sh)"
  ')" || return 1

  if [[ -z "$kv" ]]; then
    print -u2 "secrets-load: item '$METR_SECRETS_ITEM' has no custom fields"
    return 1
  fi

  eval "$kv"
  export _METR_SECRETS_LOADED=1
}

# Replace each listed command with a wrapper that loads credentials first and
# aborts if it can't. Installed on the first prompt rather than at source time,
# so ~/.zshrc.local has already had its chance to extend the list.
_metr_install_secret_wrappers() {
  local cmd
  for cmd in $METR_SECRET_COMMANDS; do
    functions[$cmd]='
      if ! secrets-load; then
        print -u2 -P "%F{red}$0: aborted%f - credentials unavailable."
        return 1
      fi
      command '"$cmd"' "$@"
    '
  done
  add-zsh-hook -d precmd _metr_install_secret_wrappers
  unfunction _metr_install_secret_wrappers
}

# Safety net for invocations the wrappers can't see, e.g. `uv run status-dashboard`,
# where the first word is `uv`. preexec cannot cancel a command, so this can only
# warn — the wrappers above are what actually enforce.
_metr_secrets_preexec() {
  [[ -n "$_METR_SECRETS_LOADED" ]] && return
  local first=${1%% *}
  # Direct invocations are handled by the wrappers; don't warn twice.
  (( ${METR_SECRET_COMMANDS[(Ie)$first]} )) && return
  local cmd
  for cmd in $METR_SECRET_COMMANDS; do
    if [[ "$1" == *"$cmd"* ]]; then
      secrets-load || true
      return
    fi
  done
}

autoload -Uz add-zsh-hook 2>/dev/null || return
add-zsh-hook precmd _metr_install_secret_wrappers
add-zsh-hook preexec _metr_secrets_preexec
