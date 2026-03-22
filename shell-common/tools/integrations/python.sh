#!/bin/sh
# shell-common/tools/integrations/python.sh

# Add user-installed Python scripts to the PATH (for pip packages like gemini-cli)
export PATH="$HOME/.local/bin:$PATH"

# Python Virtual Environment
# pyenv-virtualenv: deactivate must be sourced. Run 'source deactivate' instead of 'deactivate'
alias create-venv='python -m venv .venv'
alias act-venv='. .venv/bin/activate'
alias echo-venv='echo "$VIRTUAL_ENV"'
alias rm-venv='rm -rf .venv'
alias deact-venv='source deactivate'

alias cv='python -m venv .venv'
alias av='. .venv/bin/activate'
alias ev='echo $VIRTUAL_ENV'
alias rv='rm -rf .venv'
alias dv='source deactivate'
