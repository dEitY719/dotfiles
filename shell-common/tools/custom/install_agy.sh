#!/bin/bash
# shell-common/tools/custom/install_agy.sh
# Antigravity CLI (agy) 설치 스크립트 (대화형)
# 공식 설치: curl -fsSL https://antigravity.google/cli/install.sh | bash

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

INSTALL_URL="https://antigravity.google/cli/install.sh"

# Main script
main() {
    clear
    ux_header "Antigravity CLI (agy) Installer"
    ux_info "This script installs the Antigravity CLI (agy) via the official install script."

    ux_section "Setup Process"
    ux_numbered 1 "Check for curl."
    ux_numbered 2 "Run the official install script (${INSTALL_URL})."
    ux_numbered 3 "Verify the installation."
    echo ""

    ux_warning "The official installer may modify your shell profile (PATH/aliases)."
    ux_info "dotfiles manages ~/.local/bin via shell-common/env/path.sh (PATH SSOT)."
    ux_info "If PATH duplication appears afterward, remove the installer-added lines."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check curl
    # ========================================
    ux_step "1/3" "Checking for curl..."
    if ! ux_require "curl"; then exit 1; fi
    ux_success "curl is installed: $(curl --version | head -n1)"
    echo ""

    # ========================================
    # Step 2: Install Antigravity CLI
    # ========================================
    ux_step "2/3" "Installing Antigravity CLI..."
    if ux_confirm "Run '${INSTALL_URL}' installer now?" "y"; then
        if ! ux_with_spinner "Installing agy" bash -c "curl -fsSL '${INSTALL_URL}' | bash"; then
            ux_error "Antigravity CLI installation failed."
            exit 1
        fi
    else
        ux_info "Step 2 skipped by user."
        echo ""
        ux_header "Antigravity CLI Setup Finished"
        exit 0
    fi

    # ========================================
    # Step 3: Verify installation
    # ========================================
    ux_step "3/3" "Verifying installation..."
    if command -v agy >/dev/null 2>&1; then
        ux_success "Antigravity CLI command found: $(command -v agy)"
        agy --version || ux_warning "Could not determine agy version."
    else
        ux_error "agy command not found after installation."
        ux_warning "Check your PATH and restart your terminal."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "Antigravity CLI Setup Complete!"
    ux_section "Next Steps"
    ux_bullet "Check your PATH if the command is not found: ${UX_PRIMARY}echo \$PATH${UX_RESET}"
    ux_bullet "View help: ${UX_PRIMARY}agy --help${UX_RESET}"
    echo ""
    ux_info "For more project-specific commands, run: ${UX_PRIMARY}agy-help${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
