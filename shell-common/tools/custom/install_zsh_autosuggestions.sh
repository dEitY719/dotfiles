#!/bin/bash
# mytool/install_zsh_autosuggestions.sh
# Install and configure zsh-autosuggestions

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

# Check if zsh-autosuggestions is already installed
_check_installed() {
    # Check if installed via package manager
    if dpkg -l | grep -q zsh-autosuggestions 2>/dev/null || \
       rpm -qa | grep -q zsh-autosuggestions 2>/dev/null || \
       pacman -Q zsh-autosuggestions &>/dev/null; then
        ux_warning "zsh-autosuggestions is already installed via package manager."
        return 0
    fi

    # Check if installed via Oh My Zsh
    if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        ux_warning "zsh-autosuggestions is already installed via Oh My Zsh."
        return 0
    fi

    # Check if manually installed
    if [ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
        ux_warning "zsh-autosuggestions is already installed manually."
        return 0
    fi

    return 1
}

# Install zsh-autosuggestions via system package manager
_install_zsh_autosuggestions() {
    local rc=0
    pkg_install apt=zsh-autosuggestions pacman=zsh-autosuggestions brew=zsh-autosuggestions || rc=$?
    # rc 2 = no usable manager (yum has no package): git method, as before.
    # A real install failure still aborts instead of being masked by git.
    if [ "$rc" -eq 2 ]; then
        ux_info "Installing zsh-autosuggestions via git (no package available)..."
        _install_git_method
        return $?
    fi
    [ "$rc" -eq 0 ] || return "$rc"

    ux_success "zsh-autosuggestions installed successfully."
}

# Install via git (alternative method)
_install_git_method() {
    if ! command -v git &>/dev/null; then
        ux_error "git is required for this installation method"
        return 1
    fi

    # Check if Oh My Zsh is installed
    if [ -d "$HOME/.oh-my-zsh" ]; then
        ux_info "Installing to Oh My Zsh custom plugins..."
        git clone https://github.com/zsh-users/zsh-autosuggestions \
            "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
        ux_info "Add 'zsh-autosuggestions' to plugins in your ~/.zshrc"
    else
        ux_info "Installing to ~/.zsh/zsh-autosuggestions..."
        mkdir -p "$HOME/.zsh"
        git clone https://github.com/zsh-users/zsh-autosuggestions \
            "$HOME/.zsh/zsh-autosuggestions"
        ux_info "Add the following line to your ~/.zshrc:"
        ux_bullet "source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
    fi
}

# Display usage examples
_show_usage() {
    ux_section "zsh-autosuggestions Quick Reference"
    ux_info ""
    ux_info "How it works:"
    ux_bullet "Start typing a command - suggestions appear in gray"
    ux_bullet "Press RIGHT ARROW or END to accept suggestion"
    ux_bullet "Press CTRL+F to accept suggestion (alternative)"
    ux_bullet "Press ALT+F to accept first word only"
    ux_info ""
    ux_info "Configuration (~/.zshrc):"
    ux_bullet "For Oh My Zsh users:"
    ux_bullet_sub "plugins=(git zsh-autosuggestions ...)"
    ux_info ""
    ux_bullet "For manual installation:"
    ux_bullet_sub "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh (system package)"
    ux_bullet_sub "source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh (manual clone)"
    ux_info ""
    ux_info "Tips:"
    ux_bullet "Suggestions based on command history"
    ux_bullet "Works with any zsh theme"
    ux_bullet "Combine with zsh-syntax-highlighting for best experience"
    ux_info ""
}

# Usage text for -h/--help (#2265): no install, no external tool call.
install_zsh_autosuggestions_help() {
    ux_usage "install-zsh-autosuggestions" "" "Install zsh-autosuggestions via the system package manager, falling back to git"
}

# Main installation flow
install-zsh-autosuggestions() {
    case "${1:-}" in -h | --help) install_zsh_autosuggestions_help; return 0 ;; esac
    ux_header "zsh-autosuggestions Installation"

    # Check if zsh is installed
    if ! command -v zsh &>/dev/null; then
        ux_error "zsh is not installed. Install zsh first:"
        ux_info "  sudo apt-get install zsh  (Ubuntu/Debian)"
        ux_info "  brew install zsh          (macOS)"
        return 1
    fi

    if _check_installed; then
        ux_info "zsh-autosuggestions is ready to use!"
        _show_usage
        return 0
    fi

    _install_zsh_autosuggestions

    ux_success "zsh-autosuggestions installation complete!"
    ux_info ""
    ux_info "Next steps:"
    ux_bullet "Add zsh-autosuggestions to your ~/.zshrc configuration"
    ux_bullet "Run: source ~/.zshrc  (or restart your terminal)"
    ux_info ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    install-zsh-autosuggestions "$@"
fi
