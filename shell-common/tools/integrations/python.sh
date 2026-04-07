#!/bin/sh
# shell-common/tools/integrations/python.sh

# NOTE: $HOME/.local/bin PATH is managed by env/path.sh (SSOT)

# Python Virtual Environment
# pyenv-virtualenv: deactivate must be dot-sourced ('. deactivate')
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
