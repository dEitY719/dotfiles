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

work_help() {
    # Load ux_lib for consistent output
    if ! type ux_header >/dev/null 2>&1; then
        if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
            source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null
        fi
    fi

    ux_header "Work Management Commands"

    ux_section "Overview"
    ux_bullet "Integrated workflow for work tracking and documentation"
    ux_bullet "Combines: work-log (manual tracking) + make-jira (reports) + make-confluence (guides)"
    ux_bullet "All data git-tracked in dotfiles and rca-knowledge"

    ux_section "Commands"

    ux_step "1. Record Work (Manual Log Entry)" "work-log"
    echo ""
    ux_bullet "Add non-development work to weekly log"
    echo "  ${UX_MUTED}work-log add SWINNOTEAM-903 -t coordination -c Communication -T 2.5h${UX_RESET}"
    echo "  ${UX_MUTED}work-log list --today${UX_RESET}"
    echo ""

    ux_step "2. Generate Weekly Report" "make-jira"
    echo ""
    ux_bullet "Create Jira-formatted weekly report from work_log.txt"
    echo "  ${UX_MUTED}make-jira${UX_RESET}                    # Current week"
    echo "  ${UX_MUTED}make-jira --week 2026-W05${UX_RESET}    # Specific week"
    echo "  ${UX_MUTED}make-jira SWINNOTEAM-906${UX_RESET}     # Filter by key"
    echo ""
    ux_bullet "Output: rca-knowledge/docs/jira-records/YYYY-W##-report.md"
    echo ""

    ux_step "3. Transform Docs to Confluence Guides" "make-confluence"
    echo ""
    ux_bullet "Convert markdown technical docs to Confluence format"
    echo "  ${UX_MUTED}make-confluence docs/technic/file.md${UX_RESET}                        # Auto-detect category"
    echo "  ${UX_MUTED}make-confluence docs/analysis/file.md --category testing${UX_RESET}  # Explicit category"
    echo ""
    ux_bullet "Output: rca-knowledge/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md"
    echo ""

    ux_section "Workflow Examples"

    echo "${UX_HEADER}Daily Workflow:${UX_RESET}"
    echo "  1. Work happens → git commits (auto-tracked)"
    echo "  2. Manual non-dev work → work-log add"
    echo "  3. Friday: make-jira → Weekly Jira report"
    echo "  4. As needed: make-confluence → Technical guides"
    echo ""

    echo "${UX_HEADER}Weekly Cycle:${UX_RESET}"
    echo "  Mon-Fri: Regular work + work-log entries"
    echo "  Friday:  make-jira 2026-W05 → Jira report"
    echo "  Anytime: make-confluence → Knowledge base"
    echo ""

    ux_section "Data Flow"

    cat <<'EOF'
Work Input
  ├─ Git commits (post-commit hook → work_log.txt)
  ├─ work-log add (manual → work_log.txt)
  └─ Technical markdown (docs/technic/, rca-knowledge/docs/analysis/)

Processing
  ├─ make-jira: work_log.txt → Jira reports
  └─ make-confluence: markdown → Confluence guides

Output
  ├─ rca-knowledge/docs/jira-records/ (weekly reports)
  ├─ rca-knowledge/docs/confluence-guides/ (technical guides)
  └─ All git-tracked in dotfiles (multi-PC sync via symlink)
EOF

    ux_section "File Locations"

    ux_bullet "work_log.txt: ~/work_log.txt (symlink → ~/dotfiles/work/log/work_log.txt)"
    ux_bullet "Jira reports: ~/para/archive/rca-knowledge/docs/jira-records/"
    ux_bullet "Confluence guides: ~/para/archive/rca-knowledge/docs/confluence-guides/"
    ux_bullet "CLI tools: ~/dotfiles/shell-common/tools/custom/make_{jira,confluence}.sh"
    echo ""

    ux_section "Integration Points"

    ux_info "All commands are git-tracked:"
    echo "  ${UX_SUCCESS}dotfiles${UX_RESET}:                CLI tools + alias definitions"
    echo "  ${UX_SUCCESS}rca-knowledge${UX_RESET}:           Reports and guides"
    echo "  ${UX_SUCCESS}Multi-PC sync${UX_RESET}:           Symlink abstraction (automatic)"
    echo ""

    ux_divider
    ux_info "For detailed help on individual commands:"
    echo "  ${UX_SUCCESS}work-log help${UX_RESET}              # work-log manual"
    echo "  ${UX_SUCCESS}make-jira --help${UX_RESET}           # make-jira manual (if implemented)"
    echo "  ${UX_SUCCESS}make-confluence --help${UX_RESET}     # make-confluence manual (if implemented)"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# NOTE: This script only defines aliases and functions
# It does NOT auto-execute when sourced
# All functionality is on-demand via explicit function/alias calls
# ═══════════════════════════════════════════════════════════════════════════
