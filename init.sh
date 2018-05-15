#!/usr/bin/env bash

FILES=".config/termite .gitconfig .stalonetrayrc .vim .vimrc .xinitrc .xmobarrc .xmonad .xsessionrc .zsh-plugins .zshrc"

WORKDIR=$(pwd)

for FILE in $FILES; do
  rm ~/$FILE
  ln -s $WORKDIR/$FILE ~/$FILE
done
