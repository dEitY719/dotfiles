#!/bin/bash
# mytool/install_fasd.sh
# Install and configure fasd (fast access to directories and files)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if fasd is already installed
_check_installed() {
    if command -v fasd &>/dev/null; then
        ux_warning "fasd is already installed."
        fasd --version
        return 0
    fi
    return 1
}

# Install fasd via system package manager
_install_fasd() {
    ux_info "Installing fasd..."
    pkg_install apt=fasd yum=fasd pacman=fasd brew=fasd

    ux_success "fasd installed successfully."
}

# Display fasd usage examples
_show_usage() {
    ux_section "fasd Quick Reference"
    echo ""
    ux_info "Directory access:"
    ux_bullet "z <dir> - Jump to recently used directory matching <dir>"
    ux_bullet "zz <dir> - Jump to any directory (slower, more thorough search)"
    echo ""
    ux_info "File access:"
    ux_bullet "f <file> - Edit recently used file matching <file>"
    ux_bullet "ff <file> - Edit any file (slower, more thorough search)"
    echo ""
    ux_info "Ranking:"
    ux_bullet "Files and directories are ranked by frequency and recency"
    ux_bullet "Most recently accessed items appear first"
    echo ""
    ux_info "Tips:"
    ux_bullet "You don't need exact matches: 'z pr' may take you to a 'project' directory"
    ux_bullet "Use multiple terms: 'z my pro' for more specific matching"
    ux_bullet "View frecency data: fasd -l"
    echo ""
}

# Main installation flow
install-fasd() {
    ux_header "fasd Installation"

    if _check_installed; then
        ux_info "fasd is ready to use!"
        _show_usage
        return 0
    fi

    _install_fasd
    # Loaded by bash/main.bash and zsh/zshrc; never append to the symlinked rc files (#1802)
    ux_info "fasd init and aliases are loaded by bash/main.bash and zsh/zshrc."

    ux_success "fasd installation complete!"
    echo ""
    ux_info "To enable fasd in your current shell session, run:"
    echo "  ${UX_BOLD}exec ${SHELL##*/}${UX_RESET}"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install_fasd.sh" ]; then
    install-fasd
fi
