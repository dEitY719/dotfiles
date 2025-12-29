#!/bin/bash
# mytool/install-uv.sh
# UV Install Script
# Installs the UV tool by Astral.

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

# Main script
main() {
    clear
    ux_header "UV Installer"
    ux_info "This script installs 'uv', the fast Python package installer and resolver from Astral."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install UV
    # ========================================
    ux_step "1/1" "Installing or updating uv..."
    
    if command -v uv &>/dev/null; then
        ux_warning "uv appears to be already installed."
        if ! ux_confirm "Do you want to run the installer again to check for updates?" "n"; then
            ux_info "Skipping uv installation."
            echo ""
            uv --version
            exit 0
        fi
    fi
    
    local install_url="https://astral.sh/uv/install.sh"
    ux_info "Running installer from ${install_url}..."
    # The installer has its own output, so we don't use a spinner
    curl -LsSf "$install_url" | sh
    
    # The installer script gives its own success message and instructions.
    # We just need to verify and add a final summary.
    
    echo ""
    ux_section "Verification"
    # The installer modifies the environment, so we need to source the cargo env script to find `uv`
    # This might be in different places depending on how Rust was installed. Common paths:
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"
    fi

    if command -v uv &>/dev/null; then
        ux_success "uv command is now available in your PATH."
        uv --version
    else
        ux_error "uv command not found after installation."
        ux_warning "Please check the output above. You may need to restart your shell or run 'source ~/.bashrc'."
    fi

    echo ""
    ux_header "✅ UV Installation Complete"
    echo ""
}

main "$@"
