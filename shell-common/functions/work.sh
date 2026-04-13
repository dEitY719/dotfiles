#!/bin/sh
# shell-common/functions/work.sh
# Work management help function (make-jira, make-confluence, work-log)
# Supports both bash and zsh

# ═══════════════════════════════════════════════════════════════════════════
# Help Function: work_help
# ═══════════════════════════════════════════════════════════════════════════
#
# NOTE: Aliases are defined in shell-common/aliases/work-aliases.sh
# This module provides only the help function for the work management system
# ═════════════════════════════════════════════════════════════════════════════

_work_help_load_ux() {
    if ! type ux_header >/dev/null 2>&1; then
        if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
            source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null
        fi
    fi
}

_work_help_summary() {
    ux_info "Usage: work-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: integrated tracking & docs workflow"
    ux_bullet_sub "commands: work-log | make-jira | make-confluence"
    ux_bullet_sub "workflow: daily & weekly cycles"
    ux_bullet_sub "dataflow: input -> processing -> output"
    ux_bullet_sub "files: locations of logs, reports, tools"
    ux_bullet_sub "integration: git tracking & multi-PC sync"
    ux_bullet_sub "more: per-command help references"
    ux_bullet_sub "details: work-help <section>  (example: work-help commands)"
}

_work_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "commands"
    ux_bullet_sub "workflow"
    ux_bullet_sub "dataflow"
    ux_bullet_sub "files"
    ux_bullet_sub "integration"
    ux_bullet_sub "more"
}

_work_help_rows_overview() {
    ux_bullet "Integrated workflow for work tracking and documentation"
    ux_bullet "Combines: work-log (manual tracking) + make-jira (reports) + make-confluence (guides)"
    ux_bullet "All data git-tracked in dotfiles and playbook"
}

_work_help_rows_commands() {
    ux_step "1. Record Work (Manual Log Entry)" "work-log"
    ux_bullet "Add non-development work to weekly log"
    echo "  ${UX_MUTED}work-log add SWINNOTEAM-903 -t coordination -c Communication -T 2.5h${UX_RESET}"
    echo "  ${UX_MUTED}work-log list --today${UX_RESET}"

    ux_step "2. Generate Weekly Report" "make-jira"
    ux_bullet "Create Jira-formatted weekly report from work_log.txt"
    echo "  ${UX_MUTED}make-jira${UX_RESET}                    # Current week"
    echo "  ${UX_MUTED}make-jira --week 2026-W05${UX_RESET}    # Specific week"
    echo "  ${UX_MUTED}make-jira SWINNOTEAM-906${UX_RESET}     # Filter by key"
    ux_bullet "Output: playbook/docs/jira-records/YYYY-W##-report.md"

    ux_step "3. Transform Docs to Confluence Guides" "make-confluence"
    ux_bullet "Convert markdown technical docs to Confluence format"
    echo "  ${UX_MUTED}make-confluence docs/technic/file.md${UX_RESET}                        # Auto-detect category"
    echo "  ${UX_MUTED}make-confluence docs/analysis/file.md --category testing${UX_RESET}  # Explicit category"
    ux_bullet "Output: playbook/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md"
}

_work_help_rows_workflow() {
    echo "${UX_HEADER}Daily Workflow:${UX_RESET}"
    echo "  1. Work happens → git commits (auto-tracked)"
    echo "  2. Manual non-dev work → work-log add"
    echo "  3. Friday: make-jira → Weekly Jira report"
    echo "  4. As needed: make-confluence → Technical guides"
    echo "${UX_HEADER}Weekly Cycle:${UX_RESET}"
    echo "  Mon-Fri: Regular work + work-log entries"
    echo "  Friday:  make-jira 2026-W05 → Jira report"
    echo "  Anytime: make-confluence → Knowledge base"
}

_work_help_rows_dataflow() {
    cat <<'EOF'
Work Input
  ├─ Git commits (post-commit hook → work_log.txt)
  ├─ work-log add (manual → work_log.txt)
  └─ Technical markdown (docs/technic/, playbook/docs/analysis/)

Processing
  ├─ make-jira: work_log.txt → Jira reports
  └─ make-confluence: markdown → Confluence guides

Output
  ├─ playbook/docs/jira-records/ (weekly reports)
  ├─ playbook/docs/confluence-guides/ (technical guides)
  └─ All git-tracked in dotfiles (multi-PC sync via symlink)
EOF
}

_work_help_rows_files() {
    ux_bullet "work_log.txt: ~/work_log.txt (symlink → ~/para/archive/playbook/logs/work_log.txt)"
    ux_bullet "Jira reports: ~/para/archive/playbook/docs/jira-records/"
    ux_bullet "Confluence guides: ~/para/archive/playbook/docs/confluence-guides/"
    ux_bullet "CLI tools: ~/dotfiles/shell-common/tools/custom/make_{jira,confluence}.sh"
}

_work_help_rows_integration() {
    ux_info "All commands are git-tracked:"
    echo "  ${UX_SUCCESS}dotfiles${UX_RESET}:                CLI tools + alias definitions"
    echo "  ${UX_SUCCESS}playbook${UX_RESET}:           Reports and guides"
    echo "  ${UX_SUCCESS}Multi-PC sync${UX_RESET}:           Symlink abstraction (automatic)"
}

_work_help_rows_more() {
    ux_info "For detailed help on individual commands:"
    echo "  ${UX_SUCCESS}work-log help${UX_RESET}              # work-log manual"
    echo "  ${UX_SUCCESS}make-jira --help${UX_RESET}           # make-jira manual (if implemented)"
    echo "  ${UX_SUCCESS}make-confluence --help${UX_RESET}     # make-confluence manual (if implemented)"
}

_work_help_render_section() {
    ux_section "$1"
    "$2"
}

_work_help_section_rows() {
    case "$1" in
        overview|about)
            _work_help_rows_overview
            ;;
        commands|cmds|cmd)
            _work_help_rows_commands
            ;;
        workflow|examples|flow)
            _work_help_rows_workflow
            ;;
        dataflow|data|pipeline)
            _work_help_rows_dataflow
            ;;
        files|locations|paths)
            _work_help_rows_files
            ;;
        integration|integrations|git)
            _work_help_rows_integration
            ;;
        more|details|help-refs)
            _work_help_rows_more
            ;;
        *)
            ux_error "Unknown work-help section: $1"
            ux_info "Try: work-help --list"
            return 1
            ;;
    esac
}

_work_help_full() {
    ux_header "Work Management Commands"
    _work_help_render_section "Overview" _work_help_rows_overview
    _work_help_render_section "Commands" _work_help_rows_commands
    _work_help_render_section "Workflow Examples" _work_help_rows_workflow
    _work_help_render_section "Data Flow" _work_help_rows_dataflow
    _work_help_render_section "File Locations" _work_help_rows_files
    _work_help_render_section "Integration Points" _work_help_rows_integration
    ux_divider
    _work_help_rows_more
}

work_help() {
    _work_help_load_ux
    case "${1:-}" in
        ""|-h|--help|help)
            _work_help_summary
            ;;
        --list|list|section|sections)
            _work_help_list_sections
            ;;
        --all|all)
            _work_help_full
            ;;
        *)
            _work_help_section_rows "$1"
            ;;
    esac
}

alias work-help='work_help'

# ═══════════════════════════════════════════════════════════════════════════
# NOTE: This script only defines aliases and functions
# It does NOT auto-execute when sourced
# All functionality is on-demand via explicit function/alias calls
# ═══════════════════════════════════════════════════════════════════════════
