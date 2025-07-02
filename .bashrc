#
# ~/.bashrc
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '
# PS1='$ '
TERMINAL=st
BROWSER=chromium

alias i="sudo pacman -S"
alias u="sudo pacman -Syu"
alias r="sudo pacman -Rs"
alias ls='ls --color=auto'
alias la='ls -alt'

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH=$BUN_INSTALL/bin:$PATH
export XDG_DEFAULT_FILE_MANAGER=thunar
