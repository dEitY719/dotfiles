#!/bin/sh
# shell-common/functions/term_help.sh
# Help registry entry for term-rename / future term-* utilities.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_term_help_summary() {
    ux_info "Usage: term-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "rename     term-rename <name> | --persist <name> | --clear   set VSCode tab name"
    ux_bullet_sub "vscode     settings.json one-time setup for \${sequence}"
    ux_bullet_sub "details    term-help <section>  (example: term-help rename)"
}

_term_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "rename"
    ux_bullet_sub "vscode"
}

_term_help_rows_rename() {
    ux_table_row "term-rename <name>" "One-shot OSC 0 emit"
    ux_table_row "term-rename --persist <name>" "Re-apply on every prompt (PROMPT_COMMAND / precmd_functions hook)"
    ux_table_row "term-rename --clear" "Remove the persist hook + emit empty OSC"
    ux_table_row "sanitize" "ESC / BEL / newline / NUL stripped from <name>"
    ux_table_row "exit codes" "0 success · 1 missing/empty name · 1 unknown flag"
}

_term_help_rows_vscode() {
    ux_bullet "Default \"terminal.integrated.tabs.title\": \"\${process}\" ignores OSC titles"
    ux_bullet "Switch to \"\${sequence}\" so the shell can drive the tab label"
    ux_bullet "Optional: \"terminal.integrated.tabs.description\": \"\${process}\" keeps hover info"
}

_term_help_render_section() {
    ux_section "$1"
    "$2"
}

_term_help_section_rows() {
    case "$1" in
        rename) _term_help_rows_rename ;;
        vscode|settings|setup) _term_help_rows_vscode ;;
        *)
            ux_error "Unknown term-help section: $1"
            ux_info "Try: term-help --list"
            return 1
            ;;
    esac
}

_term_help_full() {
    ux_header "Terminal Utilities"
    _term_help_render_section "Rename" _term_help_rows_rename
    _term_help_render_section "VSCode Setup" _term_help_rows_vscode
}

term_help() {
    case "${1:-}" in
        ""|-h|--help|help) _term_help_summary ;;
        --list|list|section|sections) _term_help_list_sections ;;
        --all|all) _term_help_full ;;
        *) _term_help_section_rows "$1" ;;
    esac
}

alias term-help='term_help'
