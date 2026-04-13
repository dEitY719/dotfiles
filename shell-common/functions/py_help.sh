#!/bin/sh
# shell-common/functions/py_help.sh

_py_help_summary() {
    ux_info "Usage: py-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: cv | av | ev | rv | dv"
    ux_bullet_sub "setup: install-py | uninstall-py"
    ux_bullet_sub "details: py-help <section>  (example: py-help commands)"
}

_py_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "setup"
}

_py_help_rows_commands() {
    ux_table_row "create-venv (cv)" "python -m venv .venv" "Create venv"
    ux_table_row "act-venv (av)" ". .venv/bin/activate" "Activate"
    ux_table_row "echo-venv (ev)" "echo \$VIRTUAL_ENV" "Show path"
    ux_table_row "rm-venv (rv)" "rm -rf .venv" "Delete venv"
    ux_table_row "deact-venv (dv)" ". deactivate" "Deactivate"
}

_py_help_rows_setup() {
    ux_table_row "install-py [version...]" "Install Script" "Install default or specific Python versions"
    ux_table_row "uninstall-py <version>" "pyenv uninstall" "Remove a specific Python version"
}

_py_help_render_section() {
    ux_section "$1"
    "$2"
}

_py_help_section_rows() {
    case "$1" in
        commands|cmds|venv) _py_help_rows_commands ;;
        setup|install|tools) _py_help_rows_setup ;;
        *)
            ux_error "Unknown py-help section: $1"
            ux_info "Try: py-help --list"
            return 1
            ;;
    esac
}

_py_help_full() {
    ux_header "Python Virtual Environment Commands"
    _py_help_render_section "Commands" _py_help_rows_commands
    _py_help_render_section "Setup Tools" _py_help_rows_setup
}

py_help() {
    case "${1:-}" in
        ""|-h|--help|help) _py_help_summary ;;
        --list|list)        _py_help_list_sections ;;
        --all|all)          _py_help_full ;;
        *)                  _py_help_section_rows "$1" ;;
    esac
}

alias py-help='py_help'
