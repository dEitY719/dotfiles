#!/bin/bash
# mytool/install_fd.sh
# Install and configure fd (fast file search tool)

set -e

# Initialize common tools environment
DOTFILES_ROOT="${HOME}/dotfiles"
source "$(dirname "$0")/init.sh" || exit 1

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

    ux_info "Installing fd for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing fd..."
            sudo apt-get install -y fd-find
        elif command -v yum &>/dev/null; then
            ux_info "Installing fd via yum..."
            sudo yum install -y fd-find
        elif command -v pacman &>/dev/null; then
            ux_info "Installing fd via pacman..."
            sudo pacman -S --noconfirm fd
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing fd via Homebrew..."
            brew install fd
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

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

# Main installation flow
install-fd() {
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
    install-fd
fi
