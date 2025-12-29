#!/bin/bash
# mytool/install-git-crypt.sh
# git-crypt 설치 스크립트 (Transparent Git encryption)

set -e

# Source the UX library

source "$(dirname "$0")/../../bash/ux_lib/ux_lib.bash"

main() {
    clear
    ux_header "git-crypt Installer"
    ux_info "This script installs git-crypt for transparent Git repository encryption."

    ux_section "git-crypt benefits"
    ux_bullet "Transparent integration with Git (automatic encryption/decryption)."
    ux_bullet "File patterns are managed via .gitattributes."
    ux_bullet "No manual 'hide'/'reveal' commands needed."
    echo ""
    ux_warning "This script may require sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check dependencies
    # ========================================
    ux_step "1/3" "Checking dependencies..."
    if ! ux_require "git"; then exit 1; fi
    ux_success "git is installed."
    if ! ux_require "gpg"; then exit 1; fi
    ux_success "gpg is installed."
    echo ""

    # ========================================
    # Step 2: Install git-crypt
    # ========================================
    ux_step "2/3" "Installing git-crypt..."
    # Prompt for sudo password upfront
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    
    # Keep sudo session alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid"' EXIT

    if command -v git-crypt &>/dev/null; then
        ux_warning "git-crypt is already installed."
        if ux_confirm "Do you want to reinstall/update it?" "n"; then
            ux_with_spinner "Reinstalling git-crypt via apt" sudo apt-get install -y --reinstall git-crypt
        else
            ux_info "Installation skipped."
        fi
    else
        ux_with_spinner "Updating apt cache" sudo apt-get update -qq
        ux_with_spinner "Installing git-crypt via apt" sudo apt-get install -y git-crypt
    fi
    echo ""

    # ========================================
    # Step 3: Verify installation
    # ========================================
    ux_step "3/3" "Verifying installation..."
    if command -v git-crypt &>/dev/null; then
        ux_success "git-crypt command found."
        git-crypt --version || ux_warning "Could not determine git-crypt version."
    else
        ux_error "git-crypt command not found after installation."
        # Clean up sudo keep-alive
        kill "$sudo_keep_alive_pid" 2>/dev/null || true
        trap - EXIT
        exit 1
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ git-crypt Installation Complete!"
    ux_section "Next Steps"
    ux_numbered 1 "Generate a GPG key if you don't have one: ${UX_PRIMARY}gpg --full-generate-key${UX_RESET}"
    ux_numbered 2 "In your repository, initialize git-crypt: ${UX_PRIMARY}git-crypt init${UX_RESET}"
    ux_numbered 3 "View project-specific help: ${UX_PRIMARY}gchelp${UX_RESET}"
    echo ""
    ux_info "For more details, run: ${UX_PRIMARY}git-crypt --help${UX_RESET}"
    echo ""

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT
}

main "$@"
