#!/bin/bash

#.config
if [[ ! -d ~/.config ]]; then
    mkdir -p ~/mine
fi

git submodule update --init --recursive

#Xresource
ln -sf $PWD/.Xresources ~/.Xresources
xrdb ~/.Xresources

# environment
ln -sf $PWD/.pam_environment ~/.pam_environment

#awesome wm ranger
#sudo apt install awesome awesome-extra
for file in $(ls .config); do
    ln -sf $PWD/.config/$file $HOME/.config/$(basename $file)
    echo ln -sf $PWD/.config/$file $HOME/.config/$(basename $file)
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

if [[ -f ~/.config/lemonade.toml  ]]; then
    mv ~/.config/lemonade.toml ~/.config/lemonade.toml.bak
fi
cp $PWD/lemonade.toml ~/.config/lemonade.toml

echo complete
