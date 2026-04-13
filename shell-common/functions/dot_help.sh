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

_dot_help_summary() {
    ux_info "Usage: dot-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: project pillars (SOLID, cross-platform, mounts)"
    ux_bullet_sub "setup: setup.sh | maintenance | diagnostics"
    ux_bullet_sub "mounts: claude bind mounts status"
    ux_bullet_sub "features: shell separation | UX | help | git | skills"
    ux_bullet_sub "commands: my-help | src | dot | ux-help"
    ux_bullet_sub "docs: SETUP_GUIDE | AGENTS | UX_GUIDELINES"
    ux_bullet_sub "details: dot-help <section>  (example: dot-help setup)"
}

_dot_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "setup"
    ux_bullet_sub "mounts"
    ux_bullet_sub "features"
    ux_bullet_sub "commands"
    ux_bullet_sub "docs"
}

_dot_help_rows_overview() {
    ux_bullet "SOLID-based shell configuration separation (bash/zsh)"
    ux_bullet "Cross-platform support (Windows WSL, macOS, Linux)"
    ux_bullet "Environment-aware setup (Internal/External PC)"
    ux_bullet "Automated Claude Code skills bind mounting"
}

_dot_help_rows_setup() {
    ux_bullet "Initial setup: ./setup.sh"
    ux_bullet "Maintenance: scripts/maintenance/fix_crlf_issue.sh"
    ux_bullet "Diagnostic: shell-common/tools/custom/check_ux_consistency.sh"
}

_dot_help_rows_mounts() {
    ux_info "Claude environment directories automatically configured"
    show_mnt 2>/dev/null
}

_dot_help_rows_features() {
    ux_numbered 1 "Shell separation: bash/ and zsh/ directories"
    ux_numbered 2 "UX guidelines: Consistent color and formatting"
    ux_numbered 3 "Help system: Type help or [function]-help for info"
    ux_numbered 4 "Git attributes: Automatic CRLF/LF line ending management"
    ux_numbered 5 "Skills integration: Claude Code tools auto-mounted"
}

_dot_help_rows_commands() {
    ux_table_row "my-help"       "List all available help topics"
    ux_table_row "src"           "Reload shell configuration"
    ux_table_row "dot"           "Navigate to dotfiles directory"
    ux_table_row "ux-help"       "View UX guidelines and semantic colors"
}

_dot_help_rows_docs() {
    ux_info "Complete setup guide: ./SETUP_GUIDE.md"
    ux_info "Project structure: ./AGENTS.md"
    ux_info "UX standards: ./shell-common/tools/ux_lib/UX_GUIDELINES.md"
}

_dot_help_render_section() {
    ux_section "$1"
    "$2"
}

_dot_help_section_rows() {
    case "$1" in
        overview|project)
            _dot_help_rows_overview
            ;;
        setup|install)
            _dot_help_rows_setup
            ;;
        mounts|mount|claude)
            _dot_help_rows_mounts
            ;;
        features|feature)
            _dot_help_rows_features
            ;;
        commands|cmds|cmd)
            _dot_help_rows_commands
            ;;
        docs|doc|documentation)
            _dot_help_rows_docs
            ;;
        *)
            ux_error "Unknown dot-help section: $1"
            ux_info "Try: dot-help --list"
            return 1
            ;;
    esac
}

_dot_help_full() {
    ux_header "Dotfiles Project Information"
    _dot_help_render_section "Project Overview" _dot_help_rows_overview
    _dot_help_render_section "Setup Information" _dot_help_rows_setup
    _dot_help_render_section "Claude Mount Status" _dot_help_rows_mounts
    _dot_help_render_section "Key Features" _dot_help_rows_features
    _dot_help_render_section "Useful Commands" _dot_help_rows_commands
    _dot_help_render_section "Documentation" _dot_help_rows_docs
}

dot_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _dot_help_summary
            ;;
        --list|list|section|sections)
            _dot_help_list_sections
            ;;
        --all|all)
            _dot_help_full
            ;;
        *)
            _dot_help_section_rows "$1"
            ;;
    esac
}

alias dot-help='dot_help'
