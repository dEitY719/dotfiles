#!/bin/bash
# mytool/install-ripgrep.sh
# Install and configure ripgrep (fast text search tool)

set -e

# Source the UX library
DOTFILES_ROOT="${HOME}/dotfiles"
source "${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"

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

    ux_info "Installing ripgrep for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing ripgrep..."
            sudo apt-get install -y ripgrep
        elif command -v yum &>/dev/null; then
            ux_info "Installing ripgrep via yum..."
            sudo yum install -y ripgrep
        elif command -v pacman &>/dev/null; then
            ux_info "Installing ripgrep via pacman..."
            sudo pacman -S --noconfirm ripgrep
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing ripgrep via Homebrew..."
            brew install ripgrep
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

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

# Main installation flow
install-ripgrep() {
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
if [ "${0##*/}" = "install-ripgrep.sh" ]; then
    install-ripgrep
fi
