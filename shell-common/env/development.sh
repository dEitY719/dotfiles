#!/bin/sh
# development.sh
# 개발 관련 환경 변수 설정

# Python

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

export PYTHONPATH="$HOME/.local/lib/python3.x/site-packages:$PYTHONPATH"
export PYTHONDONTWRITEBYTECODE=1 # .pyc 파일 생성 방지

# Node.js
export NODE_ENV='development'

# Java
export JAVA_HOME='/usr/lib/jvm/java-11-openjdk-amd64'
export PATH="$JAVA_HOME/bin:$PATH"

# Machine-specific overrides (gitignored, see development.local.example)
_local_env_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/util/local_env.sh"
[ -r "$_local_env_lib" ] && . "$_local_env_lib" && _dotfiles_source_local development
unset _local_env_lib
