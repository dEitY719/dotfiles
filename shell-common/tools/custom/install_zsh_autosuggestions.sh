#!/bin/bash
# mytool/install_zsh_autosuggestions.sh
# Install and configure zsh-autosuggestions

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

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

    ux_info "Installing zsh-autosuggestions for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2)
        if command -v apt-get &>/dev/null; then
            ux_info "Updating package manager..."
            sudo apt-get update -qq
            ux_info "Installing zsh-autosuggestions..."
            sudo apt-get install -y zsh-autosuggestions
        elif command -v yum &>/dev/null; then
            ux_info "Installing zsh-autosuggestions via git (yum package not available)..."
            _install_git_method
            return $?
        elif command -v pacman &>/dev/null; then
            ux_info "Installing zsh-autosuggestions via pacman..."
            sudo pacman -S --noconfirm zsh-autosuggestions
        else
            ux_error "No supported package manager found (apt-get, yum, or pacman required)"
            return 1
        fi
    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing zsh-autosuggestions via Homebrew..."
            brew install zsh-autosuggestions
        else
            ux_error "Homebrew is required for macOS installation"
            ux_info "Install Homebrew from: https://brew.sh"
            return 1
        fi
    fi

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
        echo "  source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
    fi
}

# Display usage examples
_show_usage() {
    ux_section "zsh-autosuggestions Quick Reference"
    echo ""
    ux_info "How it works:"
    ux_bullet "Start typing a command - suggestions appear in gray"
    ux_bullet "Press RIGHT ARROW or END to accept suggestion"
    ux_bullet "Press CTRL+F to accept suggestion (alternative)"
    ux_bullet "Press ALT+F to accept first word only"
    echo ""
    ux_info "Configuration (~/.zshrc):"
    ux_bullet "For Oh My Zsh users:"
    echo "    plugins=(git zsh-autosuggestions ...)"
    echo ""
    ux_bullet "For manual installation:"
    echo "    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    echo "    # or"
    echo "    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
    echo ""
    ux_info "Tips:"
    ux_bullet "Suggestions based on command history"
    ux_bullet "Works with any zsh theme"
    ux_bullet "Combine with zsh-syntax-highlighting for best experience"
    echo ""
}

# Main installation flow
install-zsh-autosuggestions() {
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
    echo ""
    ux_info "Next steps:"
    ux_bullet "Add zsh-autosuggestions to your ~/.zshrc configuration"
    ux_bullet "Run: source ~/.zshrc  (or restart your terminal)"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    install-zsh-autosuggestions
fi
