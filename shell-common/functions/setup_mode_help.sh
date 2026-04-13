#!/bin/sh
# shell-common/functions/setup_mode_help.sh
# Setup mode management and help functions

# Load UX library if not already loaded
if ! type ux_header >/dev/null 2>&1; then
    _ux_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/ux_lib/ux_lib.sh"
    if [ -f "$_ux_lib" ]; then
        . "$_ux_lib"
    fi
fi

# ============================================================
# Get current setup mode
# ============================================================
get_setup_mode() {
    local setup_mode_file="$HOME/.dotfiles-setup-mode"

    if [ ! -f "$setup_mode_file" ]; then
        echo "none"
        return 1
    fi

    cat "$setup_mode_file" 2>/dev/null || echo "none"
}

# ============================================================
# Get setup mode name
# ============================================================
get_setup_mode_name() {
    local mode
    mode=$(get_setup_mode)

    case "$mode" in
        1) echo "Public PC (Home environment)" ;;
        2) echo "Internal company PC (Direct connection)" ;;
        3) echo "External company PC (VPN)" ;;
        *) echo "Not configured" ;;
    esac
}

# ============================================================
# Show current setup mode
# ============================================================
show_setup_mode() {
    local mode
    mode=$(get_setup_mode)

    ux_header "Current Setup Mode"

    if [ "$mode" = "none" ]; then
        ux_warning "Setup mode not configured"
        ux_info "Run: cd ~/dotfiles && ./setup.sh"
        return 1
    fi

    local mode_name
    mode_name=$(get_setup_mode_name)

    case "$mode" in
        1)
            ux_success "Mode 1: $mode_name"
            ux_info "Expected: No proxy, No company configurations"
            ;;
        2)
            ux_success "Mode 2: $mode_name"
            ux_info "Expected: Company proxy enabled (12.26.204.100:8080)"
            ux_info "Expected: All company configurations (.local.sh files) enabled"
            ;;
        3)
            ux_success "Mode 3: $mode_name"
            ux_info "Expected: No proxy, Only VPN certificate configurations"
            ;;
    esac

    ux_section "Setup Mode File"
    ux_bullet "Path: ~/.dotfiles-setup-mode"
    ux_bullet "Content: $mode"
}

# ============================================================
# Help function for setup_mode (SSOT pattern)
# ============================================================
_setup_mode_help_summary() {
    ux_info "Usage: setup-mode-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: tracks PC environment, auto-applies settings"
    ux_bullet_sub "modes: 1=Public | 2=Internal | 3=External(VPN)"
    ux_bullet_sub "usage: show-setup-mode | setup-mode-help | setup.sh"
    ux_bullet_sub "details: setup-mode-help <section>  (example: setup-mode-help modes)"
}

_setup_mode_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "modes"
    ux_bullet_sub "usage"
}

_setup_mode_help_rows_overview() {
    ux_bullet "Tracks which environment your PC is configured for"
    ux_bullet "Automatically applies environment-specific settings"
    ux_bullet "Stored in: ~/.dotfiles-setup-mode"
}

_setup_mode_help_rows_modes() {
    ux_table_row "Mode 1" "Public PC (Home environment)" "No proxy, no company configs"
    ux_table_row "Mode 2" "Internal company PC (Direct)" "Company proxy, internal repos, CA certs"
    ux_table_row "Mode 3" "External company PC (VPN)" "No proxy, VPN certificate"
}

_setup_mode_help_rows_usage() {
    ux_table_row "show-setup-mode" "Show current mode"
    ux_table_row "setup-mode-help" "View this help"
    ux_bullet "Reconfigure: ${UX_BOLD}cd ~/dotfiles && ./setup.sh${UX_RESET}"
    ux_bullet "Check proxy: ${UX_BOLD}check-proxy${UX_RESET}"
}

_setup_mode_help_render_section() {
    ux_section "$1"
    "$2"
}

_setup_mode_help_section_rows() {
    case "$1" in
        overview|about)
            _setup_mode_help_rows_overview
            ;;
        modes|mode)
            _setup_mode_help_rows_modes
            ;;
        usage|use|commands|cmds)
            _setup_mode_help_rows_usage
            ;;
        *)
            ux_error "Unknown setup-mode-help section: $1"
            ux_info "Try: setup-mode-help --list"
            return 1
            ;;
    esac
}

_setup_mode_help_full() {
    ux_header "Setup Mode Management"
    _setup_mode_help_render_section "Overview" _setup_mode_help_rows_overview
    _setup_mode_help_render_section "Available Modes" _setup_mode_help_rows_modes
    _setup_mode_help_render_section "Usage" _setup_mode_help_rows_usage
}

setup_mode_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _setup_mode_help_summary
            ;;
        --list|list)
            _setup_mode_help_list_sections
            ;;
        --all|all)
            _setup_mode_help_full
            ;;
        *)
            _setup_mode_help_section_rows "$1"
            ;;
    esac
}

# ============================================================
# Aliases for convenient access
# ============================================================
alias show-setup-mode='show_setup_mode'
alias setup-mode-help='setup_mode_help'
