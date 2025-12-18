#!/bin/bash
# mytool/install-git-secret.sh
# git-secret 설치 스크립트 (GPG 기반 비밀 관리)

set -e

# Source the UX library
# shellcheck source=../bash/ux_lib/ux_lib.bash
source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

main() {
    clear
    ux_header "git-secret Installer"
    ux_info "This script installs git-secret for managing secrets in a Git repository."

    ux_section "git-secret Workflow"
    ux_bullet "Manually add files to be encrypted with 'git secret add'."
    ux_bullet "Run 'git secret hide' to encrypt files."
    ux_bullet "Run 'git secret reveal' after cloning to decrypt."
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
    # Step 2: Install git-secret
    # ========================================
    ux_step "2/3" "Installing git-secret..."
    # Prompt for sudo password upfront
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    
    # Keep sudo session alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    if command -v git-secret &>/dev/null; then
        ux_warning "git-secret is already installed."
        if ux_confirm "Do you want to reinstall/update it?" "n"; then
            if ! ux_with_spinner "Reinstalling git-secret via apt" sudo apt-get install -y --reinstall git-secret; then
                exit 1
            fi
        else
            ux_info "Installation skipped."
        fi
    else
        if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then
            exit 1
        fi
        if ! ux_with_spinner "Installing git-secret via apt" sudo apt-get install -y git-secret; then
            exit 1
        fi
    fi
    echo ""

    # ========================================
    # Step 3: Verify installation
    # ========================================
    ux_step "3/3" "Verifying installation..."
    if command -v git-secret &>/dev/null; then
        ux_success "git-secret command found."
        git-secret --version || ux_warning "Could not determine git-secret version."
    else
        ux_error "git-secret command not found after installation."
        exit 1
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ git-secret Installation Complete!"
    ux_section "Next Steps"
    ux_numbered 1 "Generate a GPG key if you don't have one: ${UX_PRIMARY}gpg --full-generate-key${UX_RESET}"
    ux_numbered 2 "In your repository, initialize git-secret: ${UX_PRIMARY}git secret init${UX_RESET}"
    ux_numbered 3 "View project-specific help: ${UX_PRIMARY}gshelp${UX_RESET}"
    echo ""
    ux_info "For more details, run: ${UX_PRIMARY}man git-secret${UX_RESET}"
    echo ""
}

main "$@"
