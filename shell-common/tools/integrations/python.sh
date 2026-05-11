#!/bin/sh
# shell-common/tools/integrations/python.sh
# Python venv aliases (POSIX-compatible).
# Help: `py-help` (defined in shell-common/functions/py_help.sh) lists the
# create/activate/deactivate venv shortcuts below.
#
# NOTE: $HOME/.local/bin PATH is managed by env/path.sh (SSOT)

# Python Virtual Environment
# pyenv-virtualenv: deactivate must be dot-sourced ('. deactivate')

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias create-venv='python -m venv .venv'
alias act-venv='. .venv/bin/activate'
alias echo-venv='echo "$VIRTUAL_ENV"'
alias rm-venv='rm -rf .venv'
alias deact-venv='. deactivate'

alias cv='python -m venv .venv'
alias av='. .venv/bin/activate'
alias ev='echo "$VIRTUAL_ENV"'
alias rv='rm -rf .venv'
alias dv='. deactivate'
