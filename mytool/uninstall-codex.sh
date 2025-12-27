#!/bin/bash
# mytool/uninstall-codex.sh
# Codex CLI 제거 스크립트 (대화형)

set -e

# Source the UX library

source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

# Main script
main() {
    clear
    ux_header "Codex CLI Uninstaller"
    ux_info "This script uninstalls the '@openai/codex' global npm package."
    echo ""
    ux_warning "This is a destructive action and will remove the package from your system."
    echo ""

    local codex_package="@openai/codex"

    if ! ux_confirm "Are you sure you want to uninstall the '${codex_package}' package?" "n"; then
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
    # Step 2: Uninstall Codex CLI
    # ========================================
    ux_step "2/2" "Uninstalling ${codex_package}..."
    if ! command -v codex &>/dev/null; then
        ux_success "Codex CLI does not appear to be installed. Nothing to do."
    else
        if ! ux_with_spinner "Uninstalling ${codex_package} via npm" npm uninstall -g "$codex_package"; then
            ux_error "Uninstallation failed. Please check the errors above."
            exit 1
        fi
    fi
    
    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Codex CLI Uninstallation Complete!"
    if command -v codex &>/dev/null; then
        ux_warning "The 'codex' command still exists. You may need to check your PATH or restart your shell."
    else
        ux_success "The 'codex' command has been successfully removed."
    fi
    echo ""
    ux_info "To see your remaining global packages, run: ${UX_PRIMARY}npm list -g --depth=0${UX_RESET}"
    echo ""
}

main "$@"
