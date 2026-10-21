#!/bin/bash
# mytool/install_bat.sh
# Install and configure bat (cat replacement with syntax highlighting)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if bat is already installed
_check_installed() {
    if command -v bat &>/dev/null; then
        ux_warning "bat is already installed."
        bat --version
        return 0
    fi
    return 1
}

# Install bat via system package manager
_install_bat() {
    pkg_install apt=bat yum=bat pacman=bat brew=bat

    ux_success "bat installed successfully."
}

# Display bat usage examples
_show_usage() {
    ux_section "bat Quick Reference"
    echo ""
    ux_info "Basic usage:"
    ux_bullet "bat file.txt - View file with syntax highlighting"
    ux_bullet "cat file.txt | bat - View piped content"
    ux_bullet "bat --plain file.txt - View without decorations"
    echo ""
    ux_info "Common options:"
    ux_bullet "bat -n file.txt - Show line numbers"
    ux_bullet "bat -r 5:10 file.txt - Show only lines 5-10"
    ux_bullet "bat --theme Monokai Extended - Change color theme"
    echo ""
    ux_info "Tips:"
    ux_bullet "Syntax highlighting for over 200+ languages"
    ux_bullet "Git integration - shows modifications"
    ux_bullet "Paging support - automatic pagination"
    echo ""
}

# Usage text for -h/--help (#2265): no install, no external tool call.
install_bat_help() {
    ux_usage "install-bat" "" "Install bat (cat with syntax highlighting) via the system package manager"
}

# Main installation flow
install-bat() {
    case "${1:-}" in -h | --help) install_bat_help; return 0 ;; esac
    ux_header "bat Installation"

    if _check_installed; then
        ux_info "bat is ready to use!"
        _show_usage
        return 0
    fi

    _install_bat

    ux_success "bat installation complete!"
    echo ""
    ux_info "Start using bat now:"
    echo "  ${UX_BOLD}bat --help${UX_RESET}"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install_bat.sh" ]; then
    install-bat "$@"
fi
