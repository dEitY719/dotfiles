#!/bin/sh
# work_log_help.sh - Help function for work-log command
# Provides integration with the my-help system

# Try to find and source ux_lib if not already loaded
if ! type ux_header >/dev/null 2>&1; then
    if [ -z "$SHELL_COMMON" ]; then
        if [ -n "$ZSH_VERSION" ]; then
            _WORK_LOG_HELP_DIR="${0:h}"
        else
            _WORK_LOG_HELP_DIR="$(cd "$(dirname "$0")" && pwd)"
        fi
        SHELL_COMMON="${_WORK_LOG_HELP_DIR%/functions}"
    fi
    if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null
    fi
fi

# SSOT helpers for work-log-help
_work_log_help_summary() {
    ux_info "Usage: work-log-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: manual work log for non-dev work"
    ux_bullet_sub "usage: work-log add | list | help"
    ux_bullet_sub "add: interactive & argument modes"
    ux_bullet_sub "list: list options & filters"
    ux_bullet_sub "format: output entry format"
    ux_bullet_sub "types: coordination | assessment | approval | meeting"
    ux_bullet_sub "categories: Testing | Infrastructure | Documentation | ..."
    ux_bullet_sub "tasks: common task templates"
    ux_bullet_sub "details: work-log-help <section>"
}

_work_log_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "usage"
    ux_bullet_sub "add"
    ux_bullet_sub "list"
    ux_bullet_sub "format"
    ux_bullet_sub "types"
    ux_bullet_sub "categories"
    ux_bullet_sub "tasks"
}

_work_log_help_rows_overview() {
    ux_bullet "Manual work log recording tool for non-development work"
    ux_bullet "Companion to post-commit hook for development work"
    ux_bullet "All entries are appended to ~/work_log.txt"
}

_work_log_help_rows_usage() {
    ux_bullet "work-log add [JIRA-KEY] [OPTIONS]  - Add a work log entry"
    ux_bullet "work-log list [OPTIONS]            - List recent entries"
    ux_bullet "work-log help                      - Show this help"
}

_work_log_help_rows_add() {
    ux_info "Interactive Mode:"
    ux_numbered 1 "work-log add"
    ux_bullet "System will prompt for Jira key, type, category, and time"
    ux_info "Argument Mode:"
    ux_numbered 1 "work-log add JIRA-KEY --type TYPE --category CATEGORY --time TIME"
    ux_info "Short options:"
    ux_bullet "-t, --type TYPE          (coordination|assessment|approval|meeting)"
    ux_bullet "-c, --category CATEGORY  (Testing|Infrastructure|Documentation|Communication|Training|Other)"
    ux_bullet "-T, --time TIME          (numeric: 2.5 or 2.5h)"
    ux_step "Example" "Coordination meeting on testing strategy"
    echo "  ${UX_SUCCESS}work-log add SWINNOTEAM-903${UX_RESET} ${UX_MUTED}-t coordination${UX_RESET} ${UX_MUTED}-c Communication${UX_RESET} ${UX_MUTED}-T 2.5h${UX_RESET}"
}

_work_log_help_rows_list() {
    ux_numbered 1 "work-log list              - Show last 10 entries"
    ux_numbered 2 "work-log list --count 20  - Show last 20 entries"
    ux_numbered 3 "work-log list --today     - Show today's entries"
}

_work_log_help_rows_format() {
    ux_bullet "[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | time | manual"
    ux_bullet "└─ Category: CategoryName"
}

_work_log_help_rows_types() {
    ux_bullet "coordination  - Team coordination, meetings, planning"
    ux_bullet "assessment    - Code/design reviews, evaluations"
    ux_bullet "approval      - Approval requests, sign-offs"
    ux_bullet "meeting       - Official meetings, presentations"
}

_work_log_help_rows_categories() {
    ux_bullet "Testing, Infrastructure, Documentation, Performance, Security"
    ux_bullet "Communication, Coordination, Training, Other"
}

_work_log_help_rows_tasks() {
    ux_bullet "Daily standup:  work-log add [PROJ-XXX] -t meeting -c Communication -T 0.5h"
    ux_bullet "Code review:    work-log add [PROJ-XXX] -t assessment -c Communication -T 1.5h"
    ux_bullet "Team planning:  work-log add [ADMIN-001] -t coordination -c Coordination -T 2h"
    ux_divider
    ux_info "All entries stored in: ${UX_SUCCESS}${HOME}/work_log.txt${UX_RESET} (symlink → dotfiles)"
    ux_info "Git tracking: Automatically versioned in dotfiles/shell-common/data/"
    ux_info "Use these entries for weekly reports and time tracking"
}

_work_log_help_render_section() {
    ux_section "$1"
    "$2"
}

_work_log_help_section_rows() {
    case "$1" in
        overview|about)
            _work_log_help_rows_overview
            ;;
        usage|use)
            _work_log_help_rows_usage
            ;;
        add)
            _work_log_help_rows_add
            ;;
        list|ls)
            _work_log_help_rows_list
            ;;
        format|output)
            _work_log_help_rows_format
            ;;
        types|type)
            _work_log_help_rows_types
            ;;
        categories|category|cats)
            _work_log_help_rows_categories
            ;;
        tasks|examples|common)
            _work_log_help_rows_tasks
            ;;
        *)
            ux_error "Unknown work-log-help section: $1"
            ux_info "Try: work-log-help --list"
            return 1
            ;;
    esac
}

_work_log_help_full() {
    ux_header "work-log Command"
    _work_log_help_render_section "Overview" _work_log_help_rows_overview
    _work_log_help_render_section "Usage" _work_log_help_rows_usage
    _work_log_help_render_section "Add Command" _work_log_help_rows_add
    _work_log_help_render_section "List Command" _work_log_help_rows_list
    _work_log_help_render_section "Output Format" _work_log_help_rows_format
    _work_log_help_render_section "Work Types" _work_log_help_rows_types
    _work_log_help_render_section "Categories" _work_log_help_rows_categories
    _work_log_help_render_section "Common Tasks" _work_log_help_rows_tasks
}

# Main help function
work_log_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _work_log_help_summary
            ;;
        --list|list)
            _work_log_help_list_sections
            ;;
        --all|all)
            _work_log_help_full
            ;;
        *)
            _work_log_help_section_rows "$1"
            ;;
    esac
}

alias work-log-help='work_log_help'

# NOTE: This script defines the work_log_help function only.
# It should NEVER auto-execute when sourced.
#
# The function is invoked by:
# 1. my_help_impl (from my_help.sh): work_log_help
# 2. work-log help: bash /path/to/work_log.sh help
# 3. Explicit user call: work_log_help
#
# Reason: Auto-execution during zsh initialization causes p10k instant prompt
# conflicts and pollutes shell startup with help text.
