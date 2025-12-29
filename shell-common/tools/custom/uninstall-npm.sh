#!/bin/bash
# mytool/uninstall-npm.sh
# Node.js & npm 제거 스크립트 (대화형)

set -e

# Source the UX library

source "$(dirname "$0")/../../bash/ux_lib/ux_lib.bash"

# Main script
main() {
    clear
    ux_header "Node.js & npm Uninstaller"
    ux_info "This script uninstalls Node.js and npm installed via apt."
    echo ""
    ux_warning "This is a destructive action."
    ux_error "This can also remove your global npm packages and configuration files."
    echo ""

    if ! ux_confirm "Are you sure you want to uninstall the Node.js and npm apt packages?" "n"; then
        ux_warning "Uninstallation cancelled."
        exit 0
    fi

    # Request sudo privileges
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    # ========================================
    # Step 1: Remove Node.js & npm packages
    # ========================================
    ux_step "1/3" "Uninstalling Node.js and npm packages..."
    if ! ux_with_spinner "Removing nodejs and npm apt packages" sudo apt-get remove -y nodejs npm; then
        ux_warning "Could not remove nodejs and npm packages. They may not have been installed."
    else
        ux_success "Node.js and npm packages removed."
    fi
    
    if ux_confirm "Run 'apt-get autoremove' to clean up unused dependencies?" "y"; then
        if ! ux_with_spinner "Autoremoving unused dependencies" sudo apt-get autoremove -y; then
            ux_warning "apt autoremove failed."
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Clean npm configuration
    # ========================================
    ux_step "2/3" "Cleaning up npm configuration and data..."
    if [ -d "$HOME/.npm-global" ] && ux_confirm "Remove user-level global packages directory (~/.npm-global)?" "n"; then
        rm -rf "$HOME/.npm-global"
        ux_success "Removed ~/.npm-global directory."
    fi
    if [ -d "$HOME/.npm" ] && ux_confirm "Remove npm cache directory (~/.npm)?" "n"; then
        rm -rf "$HOME/.npm"
        ux_success "Removed ~/.npm directory."
    fi
    if [ -f "$HOME/.npmrc" ] && ux_confirm "Remove npm configuration file (~/.npmrc)?" "n"; then
        rm -f "$HOME/.npmrc"
        ux_success "Removed ~/.npmrc file."
    fi
    echo ""

    # ========================================
    # Step 3: Verify uninstallation
    # ========================================
    ux_step "3/3" "Verifying uninstallation..."
    if command -v node &>/dev/null || command -v npm &>/dev/null; then
        ux_warning "A 'node' or 'npm' command still exists."
        ux_info "This could be from NVM or another installation method. Check your PATH."
        command -v node || true
        command -v npm || true
    else
        ux_success "Node.js and npm have been successfully removed from apt."
    fi

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Node.js & npm Uninstallation Complete!"
    echo ""
}

main "$@"
