#!/bin/sh
# shell-common/functions/dot_help.sh
# dot_help - Dotfiles project information and setup guidance

# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    source "${BASH_SOURCE[0]%/*}/../tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi

dot_help() {
    ux_header "Dotfiles Project Information"

    ux_section "Project Overview"
    ux_bullet "SOLID-based shell configuration separation (bash/zsh)"
    ux_bullet "Cross-platform support (Windows WSL, macOS, Linux)"
    ux_bullet "Environment-aware setup (Internal/External PC)"
    ux_bullet "Automated Claude Code skills bind mounting"
    echo ""

    ux_section "Setup Information"
    ux_bullet "Initial setup: ./setup.sh"
    ux_bullet "Maintenance: scripts/maintenance/fix_crlf_issue.sh"
    ux_bullet "Diagnostic: shell-common/tools/custom/check_ux_consistency.sh"
    echo ""

    ux_section "Claude Mount Status"
    ux_info "Claude environment directories automatically configured"
    echo ""

    # Show all mount status using dedicated function
    show_mnt 2>/dev/null
    echo ""

    ux_section "Key Features"
    ux_numbered 1 "Shell separation: bash/ and zsh/ directories"
    ux_numbered 2 "UX guidelines: Consistent color and formatting"
    ux_numbered 3 "Help system: Type help or [function]-help for info"
    ux_numbered 4 "Git attributes: Automatic CRLF/LF line ending management"
    ux_numbered 5 "Skills integration: Claude Code tools auto-mounted"
    echo ""

    ux_section "Useful Commands"
    ux_table_row "my-help"       "List all available help topics"
    ux_table_row "src"           "Reload shell configuration"
    ux_table_row "dot"           "Navigate to dotfiles directory"
    ux_table_row "ux-help"       "View UX guidelines and semantic colors"
    echo ""

    ux_section "Documentation"
    ux_info "Complete setup guide: ./SETUP_GUIDE.md"
    ux_info "Project structure: ./AGENTS.md"
    ux_info "UX standards: ./shell-common/tools/ux_lib/UX_GUIDELINES.md"
    echo ""
}

# Alias for dot-help format (using dash instead of underscore)
alias dot-help='dot_help'
