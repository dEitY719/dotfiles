#!/bin/sh
# shell-common/functions/gc_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gc_help_summary() {
    ux_info "Usage: gc-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: gc | gca"
    ux_bullet_sub "options: --amend | --no-verify | --signoff"
    ux_bullet_sub "details: gc-help <section>  (example: gc-help basic)"
}

_gc_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "options"
}

_gc_help_rows_basic() {
    ux_table_row "gc" "git commit -m" "Commit with message"
    ux_table_row "gca" "git commit --amend" "Amend last commit"
}

_gc_help_rows_options() {
    ux_table_row "--amend" "git commit --amend" "Modify last commit"
    ux_table_row "--no-verify" "git commit --no-verify" "Skip pre-commit hooks (use sparingly)"
    ux_table_row "--signoff" "git commit -s" "Add Signed-off-by trailer"
}

_gc_help_render_section() {
    ux_section "$1"
    "$2"
}

_gc_help_full() {
    ux_header "Git Commit Quick Reference"
    _gc_help_render_section "Basic" _gc_help_rows_basic
    _gc_help_render_section "Options" _gc_help_rows_options
}

_gc_help_section_rows() {
    case "$1" in
        basic)
            _gc_help_render_section "Basic" _gc_help_rows_basic
            ;;
        options)
            _gc_help_render_section "Options" _gc_help_rows_options
            ;;
        *)
            ux_error "Unknown gc-help section: $1"
            ux_info "Try: gc-help --list"
            return 1
            ;;
    esac
}

gc_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gc_help_summary
            ;;
        --list|list|section|sections)
            _gc_help_list_sections
            ;;
        --all|all)
            _gc_help_full
            ;;
        *)
            _gc_help_section_rows "$1"
            ;;
    esac
}

alias gc-help='gc_help'
