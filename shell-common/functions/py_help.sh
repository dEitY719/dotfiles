#!/bin/sh
# shell-common/functions/py_help.sh
# pyHelp - shared between bash and zsh

py_help() {
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

    ux_section "Setup Tools"
    ux_table_row "pyinstall [version...]" "Install Script" "Install default or specific Python versions"
    ux_table_row "py-uninstall <version>" "pyenv uninstall" "Remove a specific Python version"
    echo ""

    ux_section "Quick Workflow"
    ux_step 1 "${UX_SUCCESS}cv${UX_RESET}  # Create .venv"
    ux_step 2 "${UX_SUCCESS}av${UX_RESET}  # Activate"
    ux_step 3 "${UX_SUCCESS}pip install ...${UX_RESET}"
    ux_step 4 "${UX_SUCCESS}dv${UX_RESET}  # Deactivate when done"
    echo ""
}

# Alias for py-help format (using dash instead of underscore)
alias py-help='py_help'
