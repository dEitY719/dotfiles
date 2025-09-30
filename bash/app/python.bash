#!/bin/bash

# bash/app/python.bash

# Add user-installed Python scripts to the PATH (for pip packages like gemini-cli)
export PATH="$HOME/.local/bin:$PATH"


# Python Virtual Environment
alias create_venv='python -m venv .venv'
alias act_venv='source .venv/bin/activate'
alias echo_venv='echo "$VIRTUAL_ENV"'
alias rm_venv='rm -rf .venv'
alias deact_venv='deactivate'

alias cv='python -m venv .venv'
alias av='source .venv/bin/activate'
alias ev='echo $VIRTUAL_ENV'
alias rv='rm -rf .venv'
alias dv='source deactivate'
# deactivate는 source 없이도 작동합니다.
# pyenv-virtualenv: deactivate must be sourced. Run 'source deactivate' instead of 'deactivate'
