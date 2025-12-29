#!/bin/bash
# mytool/install-bat.sh
# Install and configure bat (cat replacement with syntax highlighting)

set -e

# Initialize common tools environment
DOTFILES_ROOT="${HOME}/dotfiles"
source "$(dirname "$0")/init.sh" || exit 1

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

    ux_info "Installing bat for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing bat..."
            sudo apt-get install -y bat
        elif command -v yum &>/dev/null; then
            ux_info "Installing bat via yum..."
            sudo yum install -y bat
        elif command -v pacman &>/dev/null; then
            ux_info "Installing bat via pacman..."
            sudo pacman -S --noconfirm bat
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing bat via Homebrew..."
            brew install bat
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

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

# Main installation flow
install-bat() {
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
if [ "${0##*/}" = "install-bat.sh" ]; then
    install-bat
fi
