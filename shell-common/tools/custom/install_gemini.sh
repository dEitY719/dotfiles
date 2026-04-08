#!/bin/bash
# mytool/install_gemini.sh
# Gemini CLI 설치 스크립트 (대화형)
# npm 전역 패키지: @google/gemini-cli

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

# Main script
main() {
    clear
    ux_header "Gemini CLI Installer"
    ux_info "This script installs the '@google/gemini-cli' using npm."

    ux_section "Setup Process"
    ux_numbered 1 "Check for Node.js and npm."
    ux_numbered 2 "Configure npm global path (optional)."
    ux_numbered 3 "Install the '@google/gemini-cli' npm package."
    ux_numbered 4 "Verify the installation."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check Node.js & npm
    # ========================================
    ux_step "1/4" "Checking for Node.js and npm..."
    if ! ux_require "node"; then exit 1; fi
    ux_success "Node.js is installed: $(node --version)"
    if ! ux_require "npm"; then exit 1; fi
    ux_success "npm is installed: $(npm --version)"
    echo ""

    # ========================================
    # Step 2: Configure npm global path
    # ========================================
    ux_step "2/4" "Configuring npm global path..."
    local npm_prefix="$HOME/.npm-global"
    if ux_confirm "Set npm global prefix to '${npm_prefix}'?" "y"; then
        mkdir -p "$npm_prefix"
        if ! npm config set prefix "$npm_prefix"; then
            ux_error "Failed to set npm global prefix."
            exit 1
        fi
        ux_success "npm global prefix set to: $npm_prefix"

        if ! echo "$PATH" | grep -q "$npm_prefix/bin"; then
            ux_warning "Your PATH does not seem to include the npm global bin directory."
            ux_info "Add the following to your ~/.bashrc or ~/.profile:"
            echo "  ${UX_PRIMARY}export PATH=\"\$HOME/.npm-global/bin:\$PATH\"${UX_RESET}"
        fi
    else
        ux_info "Step 2 skipped by user."
    fi
    echo ""

    # ========================================
    # Step 3: Install Gemini CLI
    # ========================================
    ux_step "3/4" "Installing Gemini CLI..."
    local gemini_package="@google/gemini-cli"
    if ux_confirm "Install the '${gemini_package}' npm package globally?" "y"; then
        if ! ux_with_spinner "Installing ${gemini_package}" npm install -g "$gemini_package"; then
            ux_error "Gemini CLI installation failed."
            exit 1
        fi
    else
        ux_info "Step 3 skipped by user."
        echo ""
        ux_header "✅ Gemini CLI Setup Finished"
        exit 0
    fi

    # ========================================
    # Step 4: Verify installation
    # ========================================
    ux_step "4/4" "Verifying installation..."
    if command -v gemini &> /dev/null; then
        ux_success "Gemini CLI command found."
        gemini --version || ux_warning "Could not determine gemini version."
    else
        ux_error "Gemini CLI command not found after installation."
        ux_warning "Check your PATH and restart your terminal."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Gemini CLI Setup Complete!"
    ux_section "Next Steps"
    ux_bullet "Check your PATH if the command is not found: ${UX_PRIMARY}echo \$PATH${UX_RESET}"
    ux_bullet "View help: ${UX_PRIMARY}gemini --help${UX_RESET}"
    echo ""
    ux_info "For more project-specific commands, run: ${UX_PRIMARY}gemini-help${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
