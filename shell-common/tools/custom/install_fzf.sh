#!/bin/bash
# mytool/install_fzf.sh
# Install and configure fzf (fuzzy finder) for bash and zsh

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if fzf is already installed
_check_installed() {
    if command -v fzf &>/dev/null; then
        ux_warning "fzf is already installed."
        fzf --version
        return 0
    fi
    return 1
}

# Install fzf via system package manager
_install_fzf() {
    ux_info "Installing fzf..."
    pkg_install apt=fzf yum=fzf pacman=fzf brew=fzf
    if [ "$PKG_INSTALL_MANAGER" = brew ]; then
        # Install shell integration
        "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc
    fi

    ux_success "fzf installed successfully."
}

# Display useful fzf key bindings
_show_key_bindings() {
    ux_section "fzf Key Bindings"
    ux_bullet "Ctrl+T - Insert selected file(s) into command line"
    ux_bullet "Ctrl+R - Search command history"
    ux_bullet "Alt+C - Change to selected directory"
    echo ""
}

# Main installation flow
install-fzf() {
    ux_header "fzf Installation"

    if _check_installed; then
        ux_info "fzf is ready to use!"
        _show_key_bindings
        return 0
    fi

    _install_fzf
    # Loaded by bash/main.bash and zsh/zshrc; never append to the symlinked rc files (#1802)
    ux_info "fzf key bindings are loaded by bash/main.bash and zsh/zshrc."

    ux_success "fzf installation complete!"
    echo ""
    ux_info "To enable fzf in your current shell session, run:"
    echo "  ${UX_BOLD}exec ${SHELL##*/}${UX_RESET}"
    echo ""
    _show_key_bindings
}

# Run installation if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    install-fzf
fi
