#!/bin/bash

#.config
if [[ ! -d ~/.config ]]; then
    mkdir -p ~/mine
fi

#awesome wm
#sudo apt install awesome awesome-extra
for file in $(ls .config); do
    ln -sf $PWD/.config/$file $HOME/.config/$(basename $file)
done

#pip
ln -sf $PWD/.pip ~/.pip

#xmonad wm
#http://www.ruanyifeng.com/blog/2017/07/xmonad.html
#sudo apt install xmonad xmobar dmenu
if [[ ! -d ~/.xmonad ]]; then
    mkdir -p ~/.xmonad
fi
ln -sf $PWD/.xmonad/xmonad.hs $HOME/.xmonad/xmonad.hs
ln -sf $PWD/.xmobarrc $HOME/.xmobarrc

echo complete
