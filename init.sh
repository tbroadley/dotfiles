#!/usr/bin/env bash

FILES=".config/termite .gitconfig .gitignore_global .profile .stalonetrayrc .vim .vimrc .xinitrc .xmobarrc .xmonad .xsessionrc .zlogout .zsh-plugins .zshrc"

WORKDIR=$(pwd)

for FILE in $FILES; do
  rm ~/$FILE
  ln -s $WORKDIR/$FILE ~/$FILE
done
