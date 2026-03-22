#!/bin/sh
# shell-common/functions/py_help.sh

py_help() {
    ux_header "Python Virtual Environment Commands"

    ux_section "Commands"
    ux_table_row "create-venv (cv)" "python -m venv .venv" "Create venv"
    ux_table_row "act-venv (av)" ". .venv/bin/activate" "Activate"
    ux_table_row "echo-venv (ev)" "echo \$VIRTUAL_ENV" "Show path"
    ux_table_row "rm-venv (rv)" "rm -rf .venv" "Delete venv"
    ux_table_row "deact-venv (dv)" ". deactivate" "Deactivate"

    ux_section "Setup Tools"
    ux_table_row "install-py [version...]" "Install Script" "Install default or specific Python versions"
    ux_table_row "uninstall-py <version>" "pyenv uninstall" "Remove a specific Python version"
}

alias py-help='py_help'
