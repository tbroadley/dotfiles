# History search with arrow keys
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Go
export PATH="$PATH:/usr/local/go/bin"
export PATH="$PATH:$HOME/go/bin"

# Cargo/Rust
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# PostgreSQL
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"

# OrbStack
export PATH="$PATH:$HOME/.orbstack/bin"

# Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# Local binaries (apf, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Aliases
alias c=clear
alias d=docker
alias f='pnpm -w fmt && pnpm -w lint'
alias g=git
alias k=kubectl
alias kc='kubectl config use-context'
alias p=pnpm
alias psa='dvc push && git push'
alias t='pnpm -w typecheck'
alias tf=terraform
alias v=vim
alias cl=claude
alias clc='claude --continue'
alias clr='claude --resume'

# Completions
autoload -Uz compinit && compinit

# Git branch in prompt (vcs_info)
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
RPROMPT='${vcs_info_msg_0_}'
zstyle ':vcs_info:git:*' formats '%b'

# Docker helper functions
ds() {
    docker start $1
}
dsr() {
    ds "$(docker ps -aq --filter=label=runId=$1)"
}
de() {
    ds $1
    docker exec -it $1 bash
}
der() {
    dsr $1
    de "$(docker ps -aq --filter=label=runId=$1)"
}

# Dev container functions (auto-reload from devc.zsh before running)
source ~/dotfiles/devc.zsh
unalias dc dcr 2>/dev/null

dc() {
    source ~/dotfiles/devc.zsh
    devc "$@"
}

dcr() {
    source ~/dotfiles/devc.zsh
    devc --rebuild "$@"
}

# Local config (secrets, machine-specific settings)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
