#!/bin/sh

# shell-common/env/editor.sh
# 에디터 관련 환경 변수 설정

# 기본 에디터 설정

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

export EDITOR='vim'
export VISUAL='vim'

# Git 에디터 설정
export GIT_EDITOR='vim'
