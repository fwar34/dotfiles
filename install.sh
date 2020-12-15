#!/bin/bash

#.config
if [[ ! -d ~/.config ]]; then
    mkdir -p ~/mine
fi

for file in $(ls .config); do
    ln -sf $PWD/.config/$file $HOME/.config/$(basename $file)
done

#pip
ln -sf $PWD/.pip ~/.pip

echo complete
