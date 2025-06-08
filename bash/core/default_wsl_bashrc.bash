#!/bin/bash

# default_wsl_bashrc.bash





# non-interactive shell일 경우 종료

case $- in

    *i*) ;;

    *) return;;

esac





# 기본 설정

HISTCONTROL=ignoreboth

shopt -s histappend

HISTSIZE=1000

HISTFILESIZE=2000

shopt -s checkwinsize



# less 관련

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"



# 프롬프트 설정

if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then

    debian_chroot=$(cat /etc/debian_chroot)

fi



# 컬러 프롬프트

case "$TERM" in

    xterm-color|*-256color) color_prompt=yes;;

esac



if [ "$color_prompt" = yes ]; then

    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

else

    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '

fi

unset color_prompt



# Xterm 제목줄 설정

case "$TERM" in

xterm*|rxvt*)

    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"

    ;;

esac



# 컬러 지원 alias

if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi

    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi





# alert alias (optional, 원하는 경우만 유지)

alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'



# bash-completion 지원
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        # shellcheck source=/usr/share/bash-completion/bash_completion
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        # shellcheck source=/etc/bash_completion
        . /etc/bash_completion
    fi
fi
