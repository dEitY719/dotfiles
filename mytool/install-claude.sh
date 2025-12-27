#!/bin/bash
# mytool/install-claude.sh
# Claude Code CLI Install Script
# Installs the @anthropic-ai/claude-code global npm package.

set -e

# Source the UX library

source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

# Main script
main() {
    clear
    ux_header "Claude Code CLI Installer"
    ux_info "This script installs the '@anthropic-ai/claude-code' global npm package."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check for NVM
    # ========================================
    ux_step "1/2" "Checking for NVM (Node Version Manager)..."
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        # shellcheck source=/dev/null
        . "$HOME/.nvm/nvm.sh" # Load nvm
        ux_success "NVM is installed and loaded."
    else
        ux_error "NVM is not installed. Please install it first."
        ux_info "You can run 'install-nvm.sh' from the mytool directory."
        exit 1
    fi
    echo ""

    # ========================================
    # Step 2: Install Claude Code CLI
    # ========================================
    ux_step "2/2" "Installing '@anthropic-ai/claude-code' CLI"
    if command -v claude &>/dev/null; then
        ux_warning "Claude Code CLI seems to be already installed."
        if ! ux_confirm "Do you want to reinstall/update it?" "y"; then
            ux_info "Installation skipped."
            exit 0
        fi
    fi

    if ! ux_with_spinner "Installing @anthropic-ai/claude-code via npm" npm install -g @anthropic-ai/claude-code; then
        ux_error "Claude Code CLI installation failed."
        exit 1
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Claude Code CLI Setup Complete!"
    ux_section "Verification"
    if command -v claude &>/dev/null; then
        claude --version
        ux_success "Claude CLI is ready to use."
    else
        ux_warning "Claude command not found after installation."
        ux_info "Please restart your terminal or run 'source ~/.bashrc' to update your PATH."
    fi
    echo ""
}

main "$@"
