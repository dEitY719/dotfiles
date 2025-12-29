#!/bin/bash
# mytool/install-fasd.sh
# Install and configure fasd (fast access to directories and files)

set -e

# Source the UX library
DOTFILES_ROOT="/home/bwyoon/dotfiles"
source "${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"

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
    local os_type=""

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    else
        ux_error "Unsupported OS: $OSTYPE"
        return 1
    fi

    ux_info "Installing fasd for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing fasd..."
            sudo apt-get install -y fasd
        elif command -v yum &>/dev/null; then
            ux_info "Installing fasd via yum..."
            sudo yum install -y fasd
        elif command -v pacman &>/dev/null; then
            ux_info "Installing fasd via pacman..."
            sudo pacman -S --noconfirm fasd
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing fasd via Homebrew..."
            brew install fasd
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

    ux_success "fasd installed successfully."
}

# Configure fasd shell integration
_configure_fasd() {
    ux_info "Configuring fasd shell integration..."

    # For bash
    if [ -f "${HOME}/.bashrc" ]; then
        if ! grep -q "eval.*fasd" "${HOME}/.bashrc"; then
            ux_info "Adding fasd initialization to ~/.bashrc..."
            cat >> "${HOME}/.bashrc" << 'EOF'

# fasd initialization for fast access to directories and files
if command -v fasd &>/dev/null; then
    eval "$(fasd --init auto)"
fi
EOF
            ux_success "fasd configuration added to ~/.bashrc"
        fi
    fi

    # For zsh
    if [ -f "${HOME}/.zshrc" ]; then
        if ! grep -q "eval.*fasd" "${HOME}/.zshrc"; then
            ux_info "Adding fasd initialization to ~/.zshrc..."
            cat >> "${HOME}/.zshrc" << 'EOF'

# fasd initialization for fast access to directories and files
if command -v fasd &>/dev/null; then
    eval "$(fasd --init auto)"
fi
EOF
            ux_success "fasd configuration added to ~/.zshrc"
        fi
    fi
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
    _configure_fasd

    ux_success "fasd installation complete!"
    echo ""
    ux_info "To enable fasd in your current shell session, run:"
    echo "  ${UX_BOLD}exec ${SHELL##*/}${UX_RESET}"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install-fasd.sh" ]; then
    install-fasd
fi
