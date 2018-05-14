#!/usr/bin/env bash

FILES=".gitconfig .vim .vimrc .xinitrc .xmobarrc .xmonad .xsessionrc .zsh-plugins .zshrc"

WORKDIR=$(pwd)

cd ~

for FILE in $FILES; do
  ln -s "$WORKDIR/$FILE" "$FILE"
done
