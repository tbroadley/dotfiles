#!/usr/bin/env bash

FILES=".gitconfig .vim .vimrc"

WORKDIR=$(pwd)

cd ~

for FILE in $FILES; do
  ln -s "$WORKDIR/$FILE" "$FILE"
done
