#!/bin/bash
# mytool/uninstall-gemini.sh
# Gemini CLI 제거 스크립트 (대화형)

set -e

# Source the UX library

source "$(dirname "$0")/../../bash/ux_lib/ux_lib.bash"

# Main script
main() {
    clear
    ux_header "Gemini CLI Uninstaller"
    ux_info "This script uninstalls the '@google/gemini-cli' global npm package."
    echo ""
    ux_warning "This is a destructive action that will remove the package from your system."
    echo ""

    local gemini_package="@google/gemini-cli"

    if ! ux_confirm "Are you sure you want to uninstall the '${gemini_package}' package?" "n"; then
        ux_warning "Uninstall cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check npm
    # ========================================
    ux_step "1/2" "Checking for npm..."
    if ! ux_require "npm"; then exit 1; fi
    ux_success "npm is installed."
    echo ""
    
    # ========================================
    # Step 2: Uninstall Gemini CLI
    # ========================================
    ux_step "2/2" "Uninstalling ${gemini_package}..."
    if ! command -v gemini &>/dev/null; then
        ux_success "Gemini CLI does not appear to be installed. Nothing to do."
    else
        if ! ux_with_spinner "Uninstalling ${gemini_package} via npm" npm uninstall -g "$gemini_package"; then
            ux_error "Uninstallation failed. Please check the errors above."
            exit 1
        fi
    fi
    
    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Gemini CLI Uninstallation Complete!"
    if command -v gemini &>/dev/null; then
        ux_warning "The 'gemini' command still exists. You may need to check your PATH or restart your shell."
    else
        ux_success "The 'gemini' command has been successfully removed."
    fi
    echo ""
    ux_info "To see your remaining global packages, run: ${UX_PRIMARY}npm list -g --depth=0${UX_RESET}"
    echo ""
}

main "$@"
