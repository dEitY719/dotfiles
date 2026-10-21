#!/bin/bash
# mytool/install_ripgrep.sh
# Install and configure ripgrep (fast text search tool)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if ripgrep is already installed
_check_installed() {
    if command -v rg &>/dev/null; then
        ux_warning "ripgrep is already installed."
        rg --version
        return 0
    fi
    return 1
}

# Install ripgrep via system package manager
_install_ripgrep() {
    pkg_install apt=ripgrep yum=ripgrep pacman=ripgrep brew=ripgrep

    ux_success "ripgrep installed successfully."
}

# Display ripgrep usage examples
_show_usage() {
    ux_section "ripgrep Quick Reference"
    echo ""
    ux_info "Basic search:"
    ux_bullet "rg 'pattern' - Search for pattern in current directory"
    ux_bullet "rg 'pattern' /path - Search in specific directory"
    echo ""
    ux_info "Common options:"
    ux_bullet "rg -i 'pattern' - Case-insensitive search"
    ux_bullet "rg -w 'word' - Match whole words only"
    ux_bullet "rg -F 'literal' - Search for literal string (not regex)"
    echo ""
    ux_info "Output control:"
    ux_bullet "rg -n 'pattern' - Show line numbers (default)"
    ux_bullet "rg -c 'pattern' - Count matches only"
    ux_bullet "rg -l 'pattern' - List filenames only"
    echo ""
    ux_info "Tips:"
    ux_bullet "Much faster than grep - written in Rust"
    ux_bullet "Respects .gitignore by default - no more searching unwanted files"
    ux_bullet "Automatic parallelization - uses all CPU cores"
    echo ""
}

# Usage text for -h/--help (#2265): no install, no external tool call.
install_ripgrep_help() {
    ux_usage "install-ripgrep" "" "Install ripgrep (rg, fast text search) via the system package manager"
}

# Main installation flow
install-ripgrep() {
    case "${1:-}" in
        -h | --help) install_ripgrep_help; return 0 ;;
        # An unknown option must not fall through to a privileged install.
        -*) ux_error "unknown option: $1"; install_ripgrep_help; return 2 ;;
    esac
    ux_header "ripgrep Installation"

    if _check_installed; then
        ux_info "ripgrep is ready to use!"
        _show_usage
        return 0
    fi

    _install_ripgrep

    ux_success "ripgrep installation complete!"
    echo ""
    ux_info "Start using ripgrep now:"
    echo "  ${UX_BOLD}rg --help${UX_RESET}"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install_ripgrep.sh" ]; then
    install-ripgrep "$@"
fi
