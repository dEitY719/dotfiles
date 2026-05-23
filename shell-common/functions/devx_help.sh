#!/bin/sh
# shell-common/functions/devx_help.sh
# Help for the `devx` Type 2A dispatcher (issue #726 / #722 PR 2).
#
# Per command-design-pattern.md §7.6.1 deviation: this file defines ONLY
# the `devx_help` function. No `devx-help` alias is created — the canonical
# entry point is `devx help [section]` (with `devx`, `devx -h`, `devx
# --help` as equivalent shortcuts). Keeping the dash-form alias out
# prevents help-name conflicts with the standalone executable wrapper at
# `shell-common/tools/custom/devx.sh`.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_devx_help_summary() {
    ux_info "Usage: devx help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "lint           devx lint                  mise run lint (read-only)"
    ux_bullet_sub "fix            devx fix                   mise run fix  (mutating)"
    ux_bullet_sub "lint-helpfunc  devx lint-helpfunc         help-function registration check"
    ux_bullet_sub "lint-deadcode  devx lint-deadcode         unused _internal function check"
    ux_bullet_sub "stat           devx stat                  repo statistics (repo_stats.sh)"
    ux_bullet_sub "details        devx help <section> (example: devx help fix)"
}

_devx_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "lint"
    ux_bullet_sub "fix"
    ux_bullet_sub "lint-helpfunc"
    ux_bullet_sub "lint-deadcode"
    ux_bullet_sub "stat"
}

_devx_help_rows_lint() {
    ux_table_row "syntax" "devx lint" "Run mise run lint (read-only)"
    ux_table_row "scope" "ruff check + ruff format --check + mypy + shellcheck + shfmt -d" "All language gates"
    ux_table_row "behavior" "No file mutations" "Safe for CI / pre-commit"
}

_devx_help_rows_fix() {
    ux_table_row "syntax" "devx fix" "Run mise run fix (mutating)"
    ux_table_row "scope" "ruff check --fix + ruff format + shfmt -w" "Python + Shell auto-fix"
    ux_table_row "deprecated" "devx fmt / devx format" "Routed to fix with a one-time warning"
}

_devx_help_rows_lint_helpfunc() {
    ux_table_row "syntax" "devx lint-helpfunc" "Audit help-function registration"
    ux_table_row "checks" "Every public *_help in shell-common/functions/" "Must appear in HELP_DESCRIPTIONS"
    ux_table_row "exit" "0 = all registered, 1 = unregistered helpers found" "Pre-commit gate candidate"
}

_devx_help_rows_lint_deadcode() {
    ux_table_row "syntax" "devx lint-deadcode" "Find unused _internal functions"
    ux_table_row "checks" "^_<name>() definitions in shell-common/functions/" "1 ref = likely dead code"
    ux_table_row "exit" "0 = all in use, 1 = unused detected" "Cleanup hint, not a hard gate"
}

_devx_help_rows_stat() {
    ux_table_row "syntax" "devx stat [args]" "Run shell-common/tools/custom/repo_stats.sh"
    ux_table_row "behavior" "Args passed through to repo_stats.sh" "See repo_stats.sh -h for details"
}

_devx_help_render_section() {
    ux_section "$1"
    "$2"
}

_devx_help_section_rows() {
    case "$1" in
        lint)
            _devx_help_rows_lint
            ;;
        fix|fmt|format)
            _devx_help_rows_fix
            ;;
        lint-helpfunc)
            _devx_help_rows_lint_helpfunc
            ;;
        lint-deadcode)
            _devx_help_rows_lint_deadcode
            ;;
        stat)
            _devx_help_rows_stat
            ;;
        *)
            ux_error "Unknown devx help section: $1"
            ux_info "Try: devx help --list"
            return 1
            ;;
    esac
}

_devx_help_full() {
    ux_header "Dev Helper Commands"

    _devx_help_render_section "Lint" _devx_help_rows_lint
    _devx_help_render_section "Fix" _devx_help_rows_fix
    _devx_help_render_section "Lint-Helpfunc" _devx_help_rows_lint_helpfunc
    _devx_help_render_section "Lint-Deadcode" _devx_help_rows_lint_deadcode
    _devx_help_render_section "Stat" _devx_help_rows_stat
}

devx_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _devx_help_summary
            ;;
        --list|list|section|sections)
            _devx_help_list_sections
            ;;
        --all|all)
            _devx_help_full
            ;;
        *)
            _devx_help_section_rows "$1"
            ;;
    esac
}
