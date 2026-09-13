#!/bin/bash
# mytool/install_uv.sh
# UV Install Script
# Installs the UV tool by Astral.

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

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
    # The installer has its own output, so we don't use a spinner.
    # UV_NO_MODIFY_PATH: ~/.local/bin is on PATH via shell-common/env/path.sh.
    if ! UV_NO_MODIFY_PATH=1 run_remote_installer "$install_url"; then
        ux_error "uv installation failed."
        exit 1
    fi

    echo ""
    ux_section "Verification"
    local uv_bin="$HOME/.local/bin/uv" uv_version
    if uv_version=$(verify_installed_binary "$uv_bin" 2>&1); then
        ux_success "uv is working: $uv_version ($uv_bin)"
    else
        ux_error "uv binary is not runnable: $uv_bin"
        printf '%s\n' "$uv_version" | sed 's/^/  /'
        exit 1
    fi
    case ":$PATH:" in
        *":$(dirname "$uv_bin"):"*) ;;
        *) ux_info "Open a new terminal (or run 'rehash' in zsh) so $(dirname "$uv_bin") is on PATH." ;;
    esac

    echo ""
    ux_header "✅ UV Installation Complete"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
