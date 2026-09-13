#!/bin/bash
# mytool/install_fzf.sh
# Install and configure fzf (fuzzy finder) for bash and zsh

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

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

    ux_info "Installing fzf for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing fzf..."
            sudo apt-get install -y fzf
        elif command -v yum &>/dev/null; then
            ux_info "Installing fzf via yum..."
            sudo yum install -y fzf
        elif command -v pacman &>/dev/null; then
            ux_info "Installing fzf via pacman..."
            sudo pacman -S --noconfirm fzf
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing fzf via Homebrew..."
            brew install fzf
            # Install shell integration
            "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
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
