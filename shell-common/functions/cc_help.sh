#!/bin/sh
# shell-common/functions/cc_help.sh

_cc_help_summary() {
    ux_info "Usage: cc-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "install: npm install -g ccusage"
    ux_bullet_sub "commands: ccd | ccs | ccb"
    ux_bullet_sub "details: cc-help <section>  (example: cc-help commands)"
}

_cc_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "install"
    ux_bullet_sub "commands"
}

_cc_help_rows_install() {
    ux_bullet "Global prefix: npm install -g ccusage --prefix=\$HOME/.npm-global"
}

_cc_help_rows_commands() {
    ux_table_row "ccd" "ccusage daily --breakdown" "Token usage by model"
    ux_table_row "ccs" "ccusage session --sort tokens" "Session analysis"
    ux_table_row "ccb" "ccusage blocks --live" "Cache hit ratio (live)"
}

_cc_help_render_section() {
    ux_section "$1"
    "$2"
}

_cc_help_section_rows() {
    case "$1" in
        install|setup)      _cc_help_rows_install ;;
        commands|cmds)      _cc_help_rows_commands ;;
        *)
            ux_error "Unknown cc-help section: $1"
            ux_info "Try: cc-help --list"
            return 1
            ;;
    esac
}

_cc_help_full() {
    ux_header "Claude Code Usage Commands"
    _cc_help_render_section "Installation" _cc_help_rows_install
    _cc_help_render_section "Commands" _cc_help_rows_commands
}

cc_help() {
    case "${1:-}" in
        ""|-h|--help|help) _cc_help_summary ;;
        --list|list)        _cc_help_list_sections ;;
        --all|all)          _cc_help_full ;;
        *)                  _cc_help_section_rows "$1" ;;
    esac
}

alias cc-help='cc_help'
