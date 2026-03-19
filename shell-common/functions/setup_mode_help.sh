#!/bin/sh
# shell-common/functions/setup_mode_help.sh
# Setup mode management and help functions

# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    _ux_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/ux_lib/ux_lib.sh"
    if [ -f "$_ux_lib" ]; then
        source "$_ux_lib"
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

    echo ""
    ux_section "Setup Mode File"
    ux_bullet "Path: ~/.dotfiles-setup-mode"
    ux_bullet "Content: $mode"
    echo ""
}

# ============================================================
# Help function for setup_mode
# ============================================================
setup_mode_help() {
    ux_header "Setup Mode Management"

    ux_section "Overview"
    ux_bullet "Tracks which environment your PC is configured for"
    ux_bullet "Automatically applies environment-specific settings"
    ux_bullet "Stored in: ~/.dotfiles-setup-mode"
    echo ""

    ux_section "Available Modes"
    echo ""
    echo "  Mode 1: Public PC (Home environment)"
    echo "  ────────────────────────────────────"
    echo "    • No corporate proxy"
    echo "    • No company-specific configurations"
    echo "    • Clean home environment"
    echo ""

    echo "  Mode 2: Internal company PC (Direct connection)"
    echo "  ───────────────────────────────────────────────"
    echo "    • Company proxy: http://12.26.204.100:8080"
    echo "    • Internal repositories (Nexus)"
    echo "    • Company CA certificates"
    echo "    • McAfee proxy certificate"
    echo ""

    echo "  Mode 3: External company PC (VPN)"
    echo "  ──────────────────────────────────"
    echo "    • No company proxy (direct internet via VPN)"
    echo "    • External repositories (npmjs, PyPI, etc)"
    echo "    • VPN certificate configuration"
    echo "    • samsungsemi CA certificate"
    echo ""

    ux_section "Usage"
    ux_bullet "Show current mode: ${UX_BOLD}show-setup-mode${UX_RESET}"
    ux_bullet "Reconfigure: ${UX_BOLD}cd ~/dotfiles && ./setup.sh${UX_RESET}"
    ux_bullet "Check proxy: ${UX_BOLD}check-proxy${UX_RESET}"
    ux_bullet "View this help: ${UX_BOLD}setup-mode-help${UX_RESET}"
    echo ""
}

# ============================================================
# Aliases for convenient access
# ============================================================
alias show-setup-mode='show_setup_mode'
alias setup-mode-help='setup_mode_help'
