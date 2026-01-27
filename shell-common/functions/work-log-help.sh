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

# Main help function
work_log_help() {
    ux_header "work-log Command"

    ux_section "Overview"
    ux_bullet "Manual work log recording tool for non-development work"
    ux_bullet "Companion to post-commit hook for development work"
    ux_bullet "All entries are appended to ~/work_log.txt"

    ux_section "Usage"
    ux_bullet "work-log add [JIRA-KEY] [OPTIONS]  - Add a work log entry"
    ux_bullet "work-log list [OPTIONS]            - List recent entries"
    ux_bullet "work-log help                      - Show this help"

    ux_section "Add Command - Interactive Mode"
    ux_numbered 1 "work-log add"
    ux_bullet "System will prompt for Jira key, type, category, and time"

    ux_section "Add Command - Argument Mode"
    ux_numbered 1 "work-log add JIRA-KEY --type TYPE --category CATEGORY --time TIME"

    ux_info "Short options:"
    ux_bullet "-t, --type TYPE          (coordination|assessment|approval|meeting)"
    ux_bullet "-c, --category CATEGORY  (Testing|Infrastructure|Documentation|Communication|Training|Other)"
    ux_bullet "-T, --time TIME          (numeric: 2.5 or 2.5h)"

    echo ""
    ux_step "Example" "Coordination meeting on testing strategy"
    echo "  ${UX_SUCCESS}work-log add SWINNOTEAM-903${UX_RESET} ${UX_MUTED}-t coordination${UX_RESET} ${UX_MUTED}-c Communication${UX_RESET} ${UX_MUTED}-T 2.5h${UX_RESET}"

    ux_section "List Command"
    ux_numbered 1 "work-log list              - Show last 10 entries"
    ux_numbered 2 "work-log list --count 20  - Show last 20 entries"
    ux_numbered 3 "work-log list --today     - Show today's entries"

    ux_section "Output Format"
    ux_bullet "[YYYY-MM-DD HH:MM:SS] [JIRA-KEY] | type | category | time | manual"
    ux_bullet "└─ Category: CategoryName"

    ux_section "Work Types"
    ux_bullet "coordination  - Team coordination, meetings, planning"
    ux_bullet "assessment    - Code/design reviews, evaluations"
    ux_bullet "approval      - Approval requests, sign-offs"
    ux_bullet "meeting       - Official meetings, presentations"

    ux_section "Categories"
    ux_bullet "Testing, Infrastructure, Documentation, Performance, Security"
    ux_bullet "Communication, Coordination, Training, Other"

    ux_section "Common Tasks"
    ux_bullet "Daily standup:  work-log add [PROJ-XXX] -t meeting -c Communication -T 0.5h"
    ux_bullet "Code review:    work-log add [PROJ-XXX] -t assessment -c Communication -T 1.5h"
    ux_bullet "Team planning:  work-log add [ADMIN-001] -t coordination -c Coordination -T 2h"

    ux_divider
    ux_info "All entries stored in: ${UX_SUCCESS}${HOME}/work_log.txt${UX_RESET} (symlink → dotfiles)"
    ux_info "Git tracking: Automatically versioned in dotfiles/shell-common/data/"
    ux_info "Use these entries for weekly reports and time tracking"
}

# Only call function if this script is executed directly (not sourced)
if [ "${0##*/}" = "work-log-help.sh" ]; then
    work_log_help
fi
