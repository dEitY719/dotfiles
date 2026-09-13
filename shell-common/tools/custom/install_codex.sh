#!/bin/bash
# mytool/install_codex.sh
# Codex CLI 설치 스크립트 (대화형)
# npm 전역 패키지: codex-cli (또는 해당 패키지명)

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

# Main script
main() {
    clear
    ux_header "Codex CLI Installer"
    ux_info "This script installs the '@openai/codex' CLI using npm."

    ux_section "Setup Process"
    ux_numbered 1 "Check for Node.js and npm."
    ux_numbered 2 "Check npm global prefix (set by ~/.npmrc)."
    ux_numbered 3 "Install the '@openai/codex' npm package."
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
    # Step 2: Check npm global prefix
    # ========================================
    # ~/.npmrc is a symlink to the tracked npm/npmrc.*, which already pins
    # prefix. `npm config set` would rewrite that file through the link (#1802).
    ux_step "2/4" "Checking npm global prefix..."
    local npm_prefix="$HOME/.npm-global"
    local current_prefix
    current_prefix="$(npm config get prefix 2>/dev/null || true)"
    if [ "$current_prefix" = "$npm_prefix" ]; then
        ux_success "npm global prefix: $npm_prefix"
    else
        ux_warning "npm global prefix is '${current_prefix}', expected '${npm_prefix}'."
        ux_info "$HOME/.npmrc is a dotfiles symlink (npm/npmrc.*); re-run ./setup.sh to restore it."
    fi
    echo ""

    # ========================================
    # Step 3: Install Codex CLI
    # ========================================
    ux_step "3/4" "Installing Codex CLI..."
    local codex_package="@openai/codex"
    if ux_confirm "Install the '${codex_package}' npm package globally?" "y"; then
        if ! ux_with_spinner "Installing ${codex_package}" npm install -g "$codex_package"; then
            ux_error "Codex CLI installation failed."
            exit 1
        fi
    else
        ux_info "Step 3 skipped by user."
        echo ""
        ux_header "✅ Codex CLI Setup Complete!"
        exit 0
    fi

    # ========================================
    # Step 4: Verify installation
    # ========================================
    ux_step "4/4" "Verifying installation..."

    if command -v codex &> /dev/null; then
        ux_success "Codex CLI command found."
        codex --version || ux_warning "Could not determine codex version."
    else
        ux_error "Codex CLI command not found after installation."
        ux_warning "Check your PATH and restart your terminal."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Codex CLI Setup Complete!"
    ux_section "Next Steps"
    ux_bullet "Check your PATH if the command is not found: ${UX_PRIMARY}echo \$PATH${UX_RESET}"
    ux_bullet "View help: ${UX_PRIMARY}codex --help${UX_RESET}"
    echo ""
    ux_info "For more project-specific commands, run: ${UX_PRIMARY}codex-help${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
