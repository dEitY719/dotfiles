#!/bin/bash
# shell-common/tools/custom/install_zsh_autosuggestions.sh
# Install and configure zsh-autosuggestions plugin for command history suggestions

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

# Check if zsh-autosuggestions is already installed
_check_installed() {
    local plugin_dir="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

    if [ -d "$plugin_dir" ]; then
        ux_warning "zsh-autosuggestions is already installed."
        echo "  Location: $plugin_dir"
        return 0
    fi
    return 1
}

# Check if Oh-My-Zsh is installed
_check_omz_installed() {
    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        ux_error "Oh-My-Zsh is not installed."
        ux_info "Install Oh-My-Zsh from: https://ohmyz.sh"
        ux_info "Or run: bash -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        return 1
    fi
    return 0
}

# Install zsh-autosuggestions plugin
_install_plugin() {
    ux_info "Installing zsh-autosuggestions plugin..."

    local plugin_dir="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

    # Create custom plugins directory if needed
    mkdir -p "$(dirname "$plugin_dir")"

    # Clone the repository
    if command -v git &>/dev/null; then
        ux_info "Cloning zsh-autosuggestions repository..."
        git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$plugin_dir" 2>&1 | grep -v "^Cloning\|^remote:" || true
        ux_success "Plugin cloned successfully."
    else
        ux_error "git is required to clone zsh-autosuggestions"
        return 1
    fi
}

# Register plugin in ~/.zshrc
_register_plugin() {
    ux_info "Registering zsh-autosuggestions in ~/.zshrc..."

    local zshrc="${HOME}/.zshrc"
    if [ ! -f "$zshrc" ]; then
        ux_warning "~/.zshrc not found. Creating..."
        touch "$zshrc"
    fi

    # Check if zsh-autosuggestions is already in plugins array
    if grep -q "zsh-autosuggestions" "$zshrc"; then
        ux_warning "zsh-autosuggestions already registered in ~/.zshrc"
        return 0
    fi

    # Find and modify the plugins array
    if grep -q "plugins=(" "$zshrc"; then
        # Backup original file
        cp "$zshrc" "${zshrc}.backup.$(date +%s)" 2>/dev/null || true

        # Insert zsh-autosuggestions before the closing paren
        sed -i 's/plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$zshrc"

        ux_success "zsh-autosuggestions added to plugins array"
    else
        ux_warning "plugins=() array not found in ~/.zshrc"
        ux_info "Please add manually: plugins=(... zsh-autosuggestions)"
    fi
}

# Configure optional settings
_configure_plugin() {
    ux_info "Configuring zsh-autosuggestions..."

    local zshrc="${HOME}/.zshrc"

    # Check if configuration already exists
    if grep -q "ZSH_AUTOSUGGEST_" "$zshrc"; then
        ux_warning "zsh-autosuggestions configuration already exists"
        return 0
    fi

    # Add recommended configuration
    cat >> "$zshrc" << 'EOF'

# ═══════════════════════════════════════════════════════════════
# zsh-autosuggestions Configuration
# ═══════════════════════════════════════════════════════════════

# Suggestion strategy
export ZSH_AUTOSUGGEST_STRATEGY=(history)

# Key bindings - accept suggestion with Tab or Ctrl+Right
bindkey '^[f' autosuggest-accept        # Alt+F
bindkey '^[[1;5C' autosuggest-accept    # Ctrl+Right Arrow
bindkey -M vicmd 'q' autosuggest-accept # VI mode

# Highlight style (gray text)
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
EOF

    ux_success "Configuration added to ~/.zshrc"
}

# Display usage information
_show_info() {
    ux_section "zsh-autosuggestions Key Bindings"
    ux_bullet "Tab - Accept suggestion"
    ux_bullet "Ctrl+Right Arrow - Accept suggestion"
    ux_bullet "Alt+F - Accept suggestion"
    ux_bullet "Ctrl+W - Delete word backward"
    ux_bullet "Ctrl+U - Clear entire suggestion"
    echo ""
}

# Main installation flow
install-zsh-autosuggestions() {
    ux_header "zsh-autosuggestions Installation"
    echo ""

    # Check Oh-My-Zsh installation
    if ! _check_omz_installed; then
        return 1
    fi

    # Check if already installed
    if _check_installed; then
        ux_info "zsh-autosuggestions is ready to use!"
        _show_info
        return 0
    fi

    # Install the plugin
    _install_plugin || return 1

    # Register in ~/.zshrc
    _register_plugin || return 1

    # Configure settings
    _configure_plugin || return 1

    echo ""
    ux_success "zsh-autosuggestions installation complete!"
    echo ""
    ux_info "To enable zsh-autosuggestions in your current shell session, run:"
    echo "  ${UX_BOLD}exec zsh${UX_RESET}"
    echo ""

    _show_info

    ux_section "Next Steps"
    ux_bullet "Reload your shell: exec zsh"
    ux_bullet "Try typing a recent command and press Tab"
    ux_bullet "Customize key bindings in ~/.zshrc if desired"
    ux_bullet "Run: zsh-autosuggestions-help for more info"
    echo ""
}

# Direct-exec guard: Run only if executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    install-zsh-autosuggestions "$@"
fi
