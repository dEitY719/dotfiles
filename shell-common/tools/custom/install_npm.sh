#!/bin/bash
# mytool/install_npm.sh
# Node.js & npm 설치 스크립트 (대화형)

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "Node.js & npm Installer"
    ux_info "This script installs Node.js and npm using the system's package manager (apt)."
    
    ux_section "Setup Process"
    ux_numbered 1 "Update package sources."
    ux_numbered 2 "Install Node.js and npm."
    ux_numbered 3 "Configure a user-level directory for global packages."
    ux_numbered 4 "Upgrade npm to the latest version."
    echo ""
    ux_warning "This script requires sudo privileges for the initial installation."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi
    
    # Request sudo privileges upfront
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    # ========================================
    # Step 1: Update package manager
    # ========================================
    ux_step "1/4" "Updating package sources..."
    if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then
        ux_error "Apt update failed. Please check your connection or repository configuration."
        exit 1
    fi

    # ========================================
    # Step 2: Install Node.js & npm
    # ========================================
    ux_step "2/4" "Installing Node.js and npm..."
    if ! ux_with_spinner "Installing nodejs and npm packages" sudo apt-get install -y nodejs npm; then
        ux_error "Failed to install nodejs and npm packages."
        exit 1
    fi
    
    # ========================================
    # Step 3: Configure npm global path
    # ========================================
    ux_step "3/4" "Configuring npm global path..."
    local npm_prefix="$HOME/.npm-global"
    if ux_confirm "Set npm global prefix to '${npm_prefix}' for user-level packages?" "y"; then
        mkdir -p "$npm_prefix"
        if ! npm config set prefix "$npm_prefix"; then
            ux_error "Failed to set npm global prefix."
        else
            ux_success "npm global prefix set to: $npm_prefix"
            if ! echo "$PATH" | grep -q "$npm_prefix/bin"; then
                ux_warning "Your PATH does not seem to include the new npm global bin directory."
                ux_info "Add the following to your ~/.bashrc or ~/.profile:"
                echo "  ${UX_PRIMARY}export PATH=\"\$HOME/.npm-global/bin:\$PATH\"${UX_RESET}"
            fi
        fi
    else
        ux_info "npm global path configuration skipped."
    fi
    echo ""

    # ========================================
    # Step 4: Update npm itself
    # ========================================
    ux_step "4/4" "Upgrading npm to the latest version..."
    if ux_confirm "Upgrade npm to the latest version now?" "y"; then
        # This command should be run with the new prefix if set, so we don't use sudo
        if ! ux_with_spinner "Upgrading npm" npm install -g npm@latest; then
            ux_warning "npm upgrade failed. This is sometimes okay, but check for errors."
        fi
    else
        ux_info "npm upgrade skipped."
    fi

    # Clean up sudo keep-alive before final summary
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Node.js & npm Setup Complete!"
    ux_section "Verification"
    ux_table_header "Component" "Version/Path"
    ux_table_row "Node.js" "$(node --version 2>/dev/null || echo 'Not found')"
    ux_table_row "npm" "$(npm --version 2>/dev/null || echo 'Not found')"
    ux_table_row "npm global prefix" "$(npm config get prefix 2>/dev/null || echo 'Not set')"
    
    ux_section "Next Steps"
    ux_info "You can now install global packages, e.g.:"
    ux_bullet "${UX_PRIMARY}npm install -g typescript${UX_RESET}"
    ux_bullet "${UX_PRIMARY}npm install -g @angular/cli${UX_RESET}"
    echo ""
    ux_info "For more commands, run: ${UX_PRIMARY}npm-help${UX_RESET}"
    echo ""
}

main "$@"
