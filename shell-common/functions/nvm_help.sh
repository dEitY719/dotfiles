#!/bin/sh
# shell-common/functions/nvm_help.sh

_nvm_help_summary() {
    ux_info "Usage: nvm-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: nvm-install"
    ux_bullet_sub "usage: nvm install --lts | nvm use --lts | nvm ls"
    ux_bullet_sub "details: nvm-help <section>  (example: nvm-help usage)"
}

_nvm_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "usage"
}

_nvm_help_rows_commands() {
    ux_table_row "nvm-install" "Install Script" "Install NVM & Node LTS"
}

_nvm_help_rows_usage() {
    ux_bullet "nvm install --lts  : Install latest LTS Node"
    ux_bullet "nvm use --lts      : Use latest LTS Node"
    ux_bullet "nvm ls             : List installed versions"
}

_nvm_help_render_section() {
    ux_section "$1"
    "$2"
}

_nvm_help_section_rows() {
    case "$1" in
        commands|cmds|install) _nvm_help_rows_commands ;;
        usage)              _nvm_help_rows_usage ;;
        *)
            ux_error "Unknown nvm-help section: $1"
            ux_info "Try: nvm-help --list"
            return 1
            ;;
    esac
}

_nvm_help_full() {
    ux_header "NVM (Node Version Manager)"
    _nvm_help_render_section "Commands" _nvm_help_rows_commands
    _nvm_help_render_section "NVM Usage" _nvm_help_rows_usage
}

nvm_help() {
    case "${1:-}" in
        ""|-h|--help|help) _nvm_help_summary ;;
        --list|list|section|sections)        _nvm_help_list_sections ;;
        --all|all)          _nvm_help_full ;;
        *)                  _nvm_help_section_rows "$1" ;;
    esac
}

alias nvm-help='nvm_help'
