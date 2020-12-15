#!/bin/bash

#.config
for file in $(ls .config)
do
    ln -sf $PWD/.config/$file $HOME/.config/$(basename $file)
done

echo complete
