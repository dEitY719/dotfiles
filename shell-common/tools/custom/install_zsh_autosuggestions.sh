#!/bin/bash
# shell-common/tools/custom/install_zsh_autosuggestions.sh
# Install and configure zsh-autosuggestions plugin for command history suggestions

# Note: NOT using 'set -e' to handle errors gracefully with user-friendly messages

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

# Color codes for step indicators
readonly STEP_PENDING="○"
readonly STEP_RUNNING="◐"
readonly STEP_DONE="●"
readonly STEP_SKIP="◌"
readonly STEP_FAIL="✗"

# Display step status
_step() {
    local status="$1"
    local message="$2"
    case "$status" in
        pending) printf "[%s] %s\n" "$STEP_PENDING" "$message" ;;
        running) printf "[%s] %s" "$STEP_RUNNING" "$message"; sleep 0.3 ;;
        done) printf "\r[%s] %s\n" "$STEP_DONE" "$message" ;;
        skip) printf "[%s] %s\n" "$STEP_SKIP" "$message" ;;
        fail) printf "\r[%s] %s\n" "$STEP_FAIL" "$message" ;;
    esac
}

# Check if zsh-autosuggestions is already installed
_check_installed() {
    local plugin_dir="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    [ -d "$plugin_dir" ]
}

# Check if Oh-My-Zsh is installed
_check_omz_installed() {
    [ -d "${HOME}/.oh-my-zsh" ]
}

# Check if plugin is registered in .zshrc
_is_registered() {
    local zshrc="${HOME}/.zshrc"
    [ -f "$zshrc" ] && grep -q "zsh-autosuggestions" "$zshrc"
}

# Remove zsh-autosuggestions from plugins array (cleanup broken/incomplete installations)
_remove_from_plugins() {
    local zshrc="${HOME}/.zshrc"

    if [ ! -f "$zshrc" ] || ! grep -q "zsh-autosuggestions" "$zshrc"; then
        return 0
    fi

    # Create backup before modification
    local backup_file="${zshrc}.backup.$(date +%s)"
    cp "$zshrc" "$backup_file" || return 1

    # Remove zsh-autosuggestions from plugins array
    # Handles both "zsh-autosuggestions" and " zsh-autosuggestions "
    if sed -i.bak 's/ zsh-autosuggestions//g; s/zsh-autosuggestions //g; s/zsh-autosuggestions$//g' "$zshrc" 2>/dev/null; then
        rm -f "${zshrc}.bak" 2>/dev/null
        return 0
    else
        # Restore backup if sed failed
        cp "$backup_file" "$zshrc"
        return 1
    fi
}

# Display current status
_show_status() {
    echo ""
    ux_section "Installation Status"

    if _check_installed; then
        ux_success "✓ Plugin directory"
        echo "  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    else
        ux_warning "✗ Plugin directory not found"
    fi

    if _is_registered; then
        ux_success "✓ Registered in ~/.zshrc"
    else
        ux_warning "✗ Not registered in ~/.zshrc"
    fi
    echo ""
}

# Install zsh-autosuggestions plugin
_install_plugin() {
    local plugin_dir="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

    # Already installed
    if [ -d "$plugin_dir" ]; then
        _step skip "Plugin already cloned"
        return 0
    fi

    _step running "Cloning zsh-autosuggestions..."

    # Create custom plugins directory if needed
    mkdir -p "$(dirname "$plugin_dir")" || {
        _step fail "Failed to create plugin directory"
        return 1
    }

    # Clone the repository
    if ! command -v git &>/dev/null; then
        _step fail "git is required but not found"
        ux_error "Please install git first"
        return 1
    fi

    if git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$plugin_dir" >/dev/null 2>&1; then
        _step done "Plugin cloned successfully"
        return 0
    else
        _step fail "Failed to clone repository"
        ux_error "Could not clone from GitHub. Check your internet connection."
        return 1
    fi
}

# Register plugin in ~/.zshrc
_register_plugin() {
    local zshrc="${HOME}/.zshrc"

    # Check if already registered
    if grep -q "zsh-autosuggestions" "$zshrc" 2>/dev/null; then
        _step skip "Already registered in ~/.zshrc"
        return 0
    fi

    _step running "Registering in ~/.zshrc..."

    if [ ! -f "$zshrc" ]; then
        _step fail "~/.zshrc not found"
        ux_error "zshrc file does not exist. Please initialize zsh first:"
        echo "  zsh"
        return 1
    fi

    # Find and modify the plugins array
    if grep -q "plugins=(" "$zshrc"; then
        # Create backup
        local backup_file="${zshrc}.backup.$(date +%s)"
        cp "$zshrc" "$backup_file" || {
            _step fail "Failed to create backup"
            return 1
        }

        # Try different sed syntaxes for cross-platform compatibility
        if sed -i.bak 's/plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$zshrc" 2>/dev/null; then
            rm -f "${zshrc}.bak" 2>/dev/null
            _step done "Registered in plugins array"
            return 0
        else
            # Restore from backup if sed failed
            cp "$backup_file" "$zshrc"
            _step fail "Failed to modify plugins array"
            ux_error "Could not register plugin in ~/.zshrc"
            echo "  Backup saved: $backup_file"
            return 1
        fi
    else
        _step fail "plugins=() array not found"
        ux_error "Could not find plugins=() in ~/.zshrc"
        ux_info "Manual registration required:"
        echo "  1. Open ~/.zshrc"
        echo "  2. Find: plugins=(...)"
        echo "  3. Add: zsh-autosuggestions"
        return 1
    fi
}

# Configure optional settings
_configure_plugin() {
    local zshrc="${HOME}/.zshrc"

    # Check if configuration already exists
    if grep -q "ZSH_AUTOSUGGEST_" "$zshrc" 2>/dev/null; then
        _step skip "Configuration already exists"
        return 0
    fi

    _step running "Adding recommended configuration..."

    # Add recommended configuration
    if cat >> "$zshrc" << 'EOF'

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
    then
        _step done "Configuration added"
        return 0
    else
        _step fail "Failed to add configuration"
        return 1
    fi
}

# Display key bindings
_show_key_bindings() {
    ux_section "Key Bindings"
    ux_table_header "Key" "Action"
    ux_table_row "Tab" "Accept suggestion"
    ux_table_row "Ctrl+Right" "Accept suggestion (alternative)"
    ux_table_row "Alt+F" "Accept suggestion (VI mode)"
    ux_table_row "Ctrl+W" "Delete word backward"
    ux_table_row "Ctrl+U" "Clear entire suggestion"
    echo ""
}

# Main installation flow
install-zsh-autosuggestions() {
    ux_header "zsh-autosuggestions Installation"
    echo ""

    # Pre-flight checks
    ux_section "Pre-flight Checks"

    _step running "Checking Oh-My-Zsh..."
    if _check_omz_installed; then
        _step done "Oh-My-Zsh found"
    else
        _step fail "Oh-My-Zsh not installed"
        ux_error "Oh-My-Zsh is required to use zsh-autosuggestions"
        ux_info "Install from: https://ohmyz.sh"
        echo "  Or run: bash -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        echo ""
        return 1
    fi

    # Cleanup: Remove broken/incomplete installations first
    if _is_registered && ! _check_installed; then
        echo ""
        ux_section "Cleanup: Removing Broken Plugin Reference"
        ux_info "Found zsh-autosuggestions in ~/.zshrc but plugin not installed"
        ux_info "This causes '[oh-my-zsh] plugin not found' error when zsh starts"
        echo ""
        _step running "Removing from plugins array..."
        if _remove_from_plugins; then
            _step done "Removed broken reference"
            ux_success "✓ Zsh will no longer show plugin not found error"
        else
            ux_warning "Could not clean up ~/.zshrc, but continuing with installation..."
        fi
        echo ""
    fi

    # Check if already fully installed
    if _check_installed && _is_registered; then
        _step skip "zsh-autosuggestions is already fully installed"
        _show_status
        _show_key_bindings
        ux_success "✓ Ready to use! Run: ${UX_BOLD}exec zsh${UX_RESET}"
        echo ""
        return 0
    fi

    echo ""
    ux_section "Installation Steps"

    # Step 1: Clone plugin
    _install_plugin || {
        echo ""
        ux_error "Installation failed at plugin clone step"
        _show_status
        return 1
    }

    # Step 2: Register plugin (AFTER successful installation)
    _register_plugin || {
        echo ""
        ux_error "Installation failed at registration step"
        _show_status
        return 1
    }

    # Step 3: Configure settings
    _configure_plugin || {
        echo ""
        ux_warning "Installation mostly complete, but configuration step failed"
        ux_info "You can manually configure key bindings in ~/.zshrc if needed"
    }

    # Success!
    echo ""
    ux_success "✓ Installation complete!"
    echo ""

    # Show next steps
    ux_section "Next Steps"
    ux_bullet "Reload your shell: ${UX_BOLD}exec zsh${UX_RESET}"
    ux_bullet "Try typing a recent command and press ${UX_BOLD}Tab${UX_RESET}"
    ux_bullet "Run: ${UX_BOLD}zsh-autosuggestions-help${UX_RESET} for detailed documentation"
    echo ""

    _show_key_bindings
}

# Direct-exec guard: Run only if executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    install-zsh-autosuggestions "$@"
fi
