#!/bin/bash
# mytool/install-pet.sh
# Install and configure pet (command snippet manager)

set -e

# Source the UX library
DOTFILES_ROOT="/home/bwyoon/dotfiles"
source "${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"

# Check if pet is already installed
_check_installed() {
    if command -v pet &>/dev/null; then
        ux_warning "pet is already installed."
        pet version
        return 0
    fi
    return 1
}

# Install pet via system package manager or from releases
_install_pet() {
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

    ux_info "Installing pet for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing pet..."
            sudo apt-get install -y pet
        elif command -v yum &>/dev/null; then
            ux_info "Installing pet via yum..."
            sudo yum install -y pet
        elif command -v pacman &>/dev/null; then
            ux_info "Installing pet via pacman..."
            sudo pacman -S --noconfirm pet
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing pet via Homebrew..."
            brew install pet
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

    ux_success "pet installed successfully."
}

# Display pet usage examples
_show_usage() {
    ux_section "pet Quick Reference"
    echo ""
    ux_info "Basic commands:"
    ux_bullet "pet new - Create a new snippet"
    ux_bullet "pet search - Search and execute snippet (interactive)"
    ux_bullet "pet list - List all snippets"
    ux_bullet "pet edit - Edit snippets in editor"
    echo ""
    ux_info "Common usage:"
    ux_bullet "Store frequently used commands as snippets"
    ux_bullet "Search by description or command pattern"
    ux_bullet "Snippets stored in ~/.config/pet/snippets.toml"
    echo ""
}

# Main installation flow
install-pet() {
    ux_header "pet Installation"

    if _check_installed; then
        ux_info "pet is ready to use!"
        _show_usage
        return 0
    fi

    _install_pet

    ux_success "pet installation complete!"
    echo ""
    ux_info "Start using pet now:"
    echo "  ${UX_BOLD}pet new${UX_RESET} - Create your first snippet"
    echo "  ${UX_BOLD}pet search${UX_RESET} - Search existing snippets"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install-pet.sh" ]; then
    install-pet
fi
