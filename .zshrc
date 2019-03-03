# If you come from bash you might have to change your $PATH.
  export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
  export ZSH=/home/thomas/.oh-my-zsh

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to load
# Setting this variable when ZSH_THEME=random
# cause zsh load theme from this variable instead of
# looking in ~/.oh-my-zsh/themes/
# An empty array have no effect
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  pass
  pip
  python
  ubuntu
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
alias g=git

eval $(thefuck --alias)

source ~/.zsh-plugins/zsh-git-prompt/zshrc.sh
PROMPT='${ret_status}%{$fg[cyan]%}%c%{$reset_color%} $(git_super_status) '
GIT_PROMPT_EXECUTABLE="haskell"

HISTFILE=~/.zhist
HISTSIZE=50000
SAVEHIST=10000
setopt appendhistory autocd extendedglob nomatch notify
unsetopt beep
bindkey -v
unsetopt correct
KEYTIMEOUT=1

export RC=~/.zshrc
export DOTFILES=~/Documents/src/dotfiles

alias pbcopy='xclip -selection clipboard'
alias dirsize='du -d 1 -B 1K'
alias editrc='$EDITOR $RC'
alias reload='source $RC'
alias serve='python -m SimpleHTTPServer'
alias naut='nautilus'

export FFSTYLES=~/.mozilla/firefox/fjf2kejb.default/chrome/userContent.css

export PATH="$PATH:/usr/lib/postgresql/10/bin"

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/usr/local/bin/gcc-linaro-7.2.1-2017.11-x86_64_aarch64-elf/bin:/usr/local/bin/aarch64-none-elf/bin:$PATH"

source ~/.profile

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"

export EDITOR=vim
export VISUAL=vim

export RDEDUP_DIR="/data/backup"

alias testbackup="RDEDUP_DIR=/data/backup rdedup load $(RDEDUP_DIR=/data/backup rdedup list | sort | tail -1) | rdup-up "$HOME.restored""

alias v="vim"

export PASSWORD_STORE_ENABLE_EXTENSIONS=true
alias sshpass="eval \$(ssh-agent) && $HOME/Documents/src/misc/ssh-add-pass.ex"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# added by travis gem
[ -f /home/thomas/.travis/travis.sh ] && source /home/thomas/.travis/travis.sh

export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
export PATH="/usr/local/texlive/2018/bin/x86_64-linux:$PATH"
. $HOME/.ghcup/env
