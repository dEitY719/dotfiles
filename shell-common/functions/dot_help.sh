#!/bin/sh
# shell-common/functions/dot_help.sh

# Load UX library if not already loaded (POSIX portable)
if ! type ux_header >/dev/null 2>&1; then
    # Try multiple paths to find ux_lib.sh
    _ux_lib_paths="
        ${SHELL_COMMON}/tools/ux_lib/ux_lib.sh
        ${HOME}/.local/dotfiles/shell-common/tools/ux_lib/ux_lib.sh
        $(dirname "$0")/../tools/ux_lib/ux_lib.sh
    "

    for _ux_lib_path in $_ux_lib_paths; do
        if [ -f "$_ux_lib_path" ]; then
            # shellcheck disable=SC1090
            . "$_ux_lib_path"
            break
        fi
    done
    unset _ux_lib_path _ux_lib_paths
fi

dot_help() {
    ux_header "Dotfiles Project Information"

    ux_section "Project Overview"
    ux_bullet "SOLID-based shell configuration separation (bash/zsh)"
    ux_bullet "Cross-platform support (Windows WSL, macOS, Linux)"
    ux_bullet "Environment-aware setup (Internal/External PC)"
    ux_bullet "Automated Claude Code skills bind mounting"

    ux_section "Setup Information"
    ux_bullet "Initial setup: ./setup.sh"
    ux_bullet "Maintenance: scripts/maintenance/fix_crlf_issue.sh"
    ux_bullet "Diagnostic: shell-common/tools/custom/check_ux_consistency.sh"

    ux_section "Claude Mount Status"
    ux_info "Claude environment directories automatically configured"

    # Show all mount status using dedicated function
    show_mnt 2>/dev/null

    ux_section "Key Features"
    ux_numbered 1 "Shell separation: bash/ and zsh/ directories"
    ux_numbered 2 "UX guidelines: Consistent color and formatting"
    ux_numbered 3 "Help system: Type help or [function]-help for info"
    ux_numbered 4 "Git attributes: Automatic CRLF/LF line ending management"
    ux_numbered 5 "Skills integration: Claude Code tools auto-mounted"

    ux_section "Useful Commands"
    ux_table_row "my-help"       "List all available help topics"
    ux_table_row "src"           "Reload shell configuration"
    ux_table_row "dot"           "Navigate to dotfiles directory"
    ux_table_row "ux-help"       "View UX guidelines and semantic colors"

    ux_section "Documentation"
    ux_info "Complete setup guide: ./SETUP_GUIDE.md"
    ux_info "Project structure: ./AGENTS.md"
    ux_info "UX standards: ./shell-common/tools/ux_lib/UX_GUIDELINES.md"
}

alias dot-help='dot_help'
