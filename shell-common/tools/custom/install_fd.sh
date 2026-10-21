#!/bin/bash
# mytool/install_fd.sh
# Install and configure fd (fast file search tool)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if fd is already installed
_check_installed() {
    if command -v fd &>/dev/null; then
        ux_warning "fd is already installed."
        fd --version
        return 0
    fi
    return 1
}

# Install fd via system package manager
_install_fd() {
    pkg_install apt=fd-find yum=fd-find pacman=fd brew=fd

    ux_success "fd installed successfully."
}

# Display fd usage examples
_show_usage() {
    ux_section "fd Quick Reference"
    echo ""
    ux_info "Basic search:"
    ux_bullet "fd 'pattern' - Search for files/directories matching pattern"
    ux_bullet "fd 'pattern' /path - Search in specific directory"
    echo ""
    ux_info "Common options:"
    ux_bullet "fd -t f 'pattern' - Find files only"
    ux_bullet "fd -t d 'pattern' - Find directories only"
    ux_bullet "fd -i 'pattern' - Case-insensitive search"
    ux_bullet "fd -e .txt 'pattern' - Find with specific extension"
    echo ""
    ux_info "Tips:"
    ux_bullet "Much faster than find - written in Rust"
    ux_bullet "Respects .gitignore by default - ignore unwanted files"
    ux_bullet "Smart case sensitivity - case-insensitive unless pattern has uppercase"
    echo ""
}

# Usage text for -h/--help (#2265): no install, no external tool call.
install_fd_help() {
    ux_usage "install-fd" "" "Install fd (fast file search) via the system package manager"
}

# Main installation flow
install-fd() {
    case "${1:-}" in -h | --help) install_fd_help; return 0 ;; esac
    ux_header "fd Installation"

    if _check_installed; then
        ux_info "fd is ready to use!"
        _show_usage
        return 0
    fi

    _install_fd

    ux_success "fd installation complete!"
    echo ""
    ux_info "Start using fd now:"
    echo "  ${UX_BOLD}fd --help${UX_RESET}"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install_fd.sh" ]; then
    install-fd "$@"
fi
