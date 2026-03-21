#!/bin/sh
# shell-common/tools/integrations/python.sh

# Add user-installed Python scripts to the PATH (for pip packages like gemini-cli)
export PATH="$HOME/.local/bin:$PATH"

# Python Virtual Environment
# pyenv-virtualenv: deactivate must be sourced. Run 'source deactivate' instead of 'deactivate'
create_venv() { python -m venv .venv; }
act_venv() { . .venv/bin/activate; }
echo_venv() { echo "$VIRTUAL_ENV"; }
rm_venv() { rm -rf .venv; }
deact_venv() { source deactivate; }

alias create-venv='create_venv'
alias act-venv='act_venv'
alias echo-venv='echo_venv'
alias rm-venv='rm_venv'
alias deact-venv='deact_venv'

alias cv='create_venv'
alias av='act_venv'
alias ev='echo_venv'
alias rv='rm_venv'
alias dv='deact_venv'
