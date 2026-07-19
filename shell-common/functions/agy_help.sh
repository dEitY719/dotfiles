#!/bin/sh
# shell-common/functions/agy_help.sh
# Antigravity CLI (agy) help function

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_agy_help_summary() {
    ux_info "Usage: agy-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: agy-version | agy-continue | agy-plan | agy-models"
    ux_bullet_sub "setup: agy-install | agy-uninstall"
    ux_bullet_sub "tips: OAuth token dir | agy install PATH conflict"
    ux_bullet_sub "details: agy-help <section>  (example: agy-help basic)"
}

_agy_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "setup"
    ux_bullet_sub "tips"
}

_agy_help_rows_basic() {
    ux_table_row "agy-version" "agy --version" "Check version"
    ux_table_row "agy-continue" "agy --continue" "Continue recent conversation"
    ux_table_row "agy-plan" "agy --mode plan" "Run in plan mode"
    ux_table_row "agy-models" "agy models" "List available models"
}

_agy_help_rows_setup() {
    ux_table_row "agy-install" "Install Script" "Install Antigravity CLI"
    ux_table_row "agy-uninstall" "Uninstall Script" "Remove Antigravity CLI"
}

_agy_help_rows_tips() {
    ux_bullet "OAuth token stored in ~/.gemini/antigravity-cli/"
    ux_bullet "Use 'agy --help' for detailed CLI options"
    ux_bullet "Model list changes often — run 'agy models' directly rather than relying on the 'agy-models' alias"
    ux_bullet "agy install edits shell profiles; PATH SSOT is shell-common/env/path.sh"
    ux_bullet "Prefer: agy install --skip-path --skip-aliases"
}

_agy_help_render_section() {
    ux_section "$1"
    "$2"
}

_agy_help_section_rows() {
    case "$1" in
        basic|commands)
            _agy_help_rows_basic
            ;;
        setup|install|installation)
            _agy_help_rows_setup
            ;;
        tips|tip)
            _agy_help_rows_tips
            ;;
        *)
            ux_error "Unknown agy-help section: $1"
            ux_info "Try: agy-help --list"
            return 1
            ;;
    esac
}

_agy_help_full() {
    ux_header "Antigravity CLI (agy) Quick Commands"

    _agy_help_render_section "Basic Commands" _agy_help_rows_basic
    _agy_help_render_section "Installation & Setup" _agy_help_rows_setup
    _agy_help_render_section "Tips" _agy_help_rows_tips
}

agy_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _agy_help_summary
            ;;
        --list|list|section|sections)
            _agy_help_list_sections
            ;;
        --all|all)
            _agy_help_full
            ;;
        *)
            _agy_help_section_rows "$1"
            ;;
    esac
}

alias agy-help='agy_help'
