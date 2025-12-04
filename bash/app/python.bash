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

# -------------------------------
# Python venv 도움말
# -------------------------------
pyhelp() {
    ux_header "Python Virtual Environment Commands"

    ux_section "Full Commands"
    ux_table_row "create_venv" "python -m venv .venv" "Create venv"
    ux_table_row "act_venv" "source .venv/bin/activate" "Activate"
    ux_table_row "echo_venv" "echo \$VIRTUAL_ENV" "Show path"
    ux_table_row "rm_venv" "rm -rf .venv" "Delete venv"
    ux_table_row "deact_venv" "deactivate" "Deactivate"
    echo ""

    ux_section "Short Aliases"
    ux_table_row "cv" "create venv" "Create"
    ux_table_row "av" "activate venv" "Activate"
    ux_table_row "ev" "echo venv" "Show path"
    ux_table_row "rv" "remove venv" "Delete"
    ux_table_row "dv" "deactivate" "Deactivate"
    echo ""

    ux_section "Quick Workflow"
    ux_step 1 "${UX_SUCCESS}cv${UX_RESET}  # Create .venv"
    ux_step 2 "${UX_SUCCESS}av${UX_RESET}  # Activate"
    ux_step 3 "${UX_SUCCESS}pip install ...${UX_RESET}"
    ux_step 4 "${UX_SUCCESS}dv${UX_RESET}  # Deactivate when done"
    echo ""
}
