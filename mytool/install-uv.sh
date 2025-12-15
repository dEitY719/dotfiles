#!/bin/bash

# mytool/install-uv.sh
# UV Install Script
# Installs the UV tool by Astral.

set -e

# Color definitions
bold=$(tput bold 2>/dev/null || echo "")
blue=$(tput setaf 4 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")
reset=$(tput sgr0 2>/dev/null || echo "")

# Helper functions
info() {
    echo "${bold}${blue}[INFO]${reset} $*"
}

success() {
    echo "${bold}${green}[✓]${reset} $*"
}

warning() {
    echo "${bold}${yellow}[⚠]${reset} $*"
}

error() {
    echo "${bold}${red}[✗]${reset} $*"
}

confirm() {
    local prompt="$1"
    local response
    echo -n "${bold}${blue}${prompt}${reset} (y/n) "
    read -r response
    [[ "$response" == "y" || "$response" == "Y" ]]
}

# Main script
main() {
    clear
    cat <<EOF
${bold}${blue}════════════════════════════════════════════════════
  UV Install Script
════════════════════════════════════════════════════${reset}

This script will:
  1. Install the UV tool from astral.sh.

EOF

    if ! confirm "Continue with installation?"; then
        warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install UV
    # ========================================
    info "Step 1/1: Installing UV..."
    if command -v uv &>/dev/null; then
        warning "UV appears to be already installed."
        if ! confirm "Do you want to reinstall/update it?"; then
            info "Skipping UV installation."
            exit 0
        fi
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh
    success "UV installed/updated."

    echo ""
    echo "${bold}Verification:${reset}"
    if command -v uv &>/dev/null; then
        uv --version
    else
        warning "UV command not found after installation. Please check your PATH."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ UV Setup Complete!
════════════════════════════════════════════════════${reset}

${bold}Note:${reset}
  If 'uv --version' above failed, please restart your terminal or run
  'source ~/.bashrc' (or ~/.profile) to ensure your PATH is updated.

EOF
}

main "$@"
