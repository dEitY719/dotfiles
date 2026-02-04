#!/bin/bash
# shell-common/functions/ensure_ollama_deps.sh
# Ollama Dependency Installer
# Single Responsibility: Install system dependencies required for Ollama
# Does NOT install Ollama itself - that's install_ollama.sh's job

set -e

# Load UX library - use absolute path
source /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh 2>/dev/null || {
    echo "Warning: UX library not found" >&2
}

main() {
    ux_header "Ollama System Dependencies Installer"
    echo ""
    
    ux_section "Purpose"
    ux_info "This script installs system packages required for Ollama."
    ux_info "It does NOT install Ollama itself."
    echo ""
    
    # Detect OS/distro
    ux_section "System Detection"
    if [[ ! "$OSTYPE" == "linux-gnu"* ]]; then
        ux_error "This script is for Linux/WSL only"
        return 1
    fi
    ux_success "Running on Linux/WSL"
    echo ""
    
    # Determine package manager
    if command -v apt-get &> /dev/null; then
        ux_info "Package manager: apt-get (Debian/Ubuntu)"
        INSTALL_CMD="sudo apt-get install -y"
        REQUIRED_PKGS="zstd curl"
    elif command -v dnf &> /dev/null; then
        ux_info "Package manager: dnf (RHEL/CentOS/Fedora)"
        INSTALL_CMD="sudo dnf install -y"
        REQUIRED_PKGS="zstd curl"
    elif command -v pacman &> /dev/null; then
        ux_info "Package manager: pacman (Arch)"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        REQUIRED_PKGS="zstd curl"
    else
        ux_error "Package manager not found (apt-get, dnf, pacman required)"
        return 1
    fi
    echo ""
    
    # Check each required package
    ux_section "Dependency Check"
    MISSING_PKGS=""
    
    for pkg in $REQUIRED_PKGS; do
        # First check: command exists and is executable
        if command -v "$pkg" &> /dev/null; then
            ux_success "$pkg — already installed"
        # Second check: exact package name match in dpkg (avoid matching libzstd1 when checking for zstd)
        elif dpkg -l 2>/dev/null | awk "/^ii/ {print \$2}" | grep -q "^${pkg}$"; then
            ux_success "$pkg — already installed"
        else
            ux_error "$pkg — NOT installed (required)"
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done
    echo ""
    
    # Install missing packages
    if [ -z "$MISSING_PKGS" ]; then
        ux_success "All dependencies are already installed!"
        return 0
    fi
    
    ux_section "Installing Missing Packages"
    ux_info "Packages to install:$MISSING_PKGS"
    echo ""
    
    # Confirm before installing
    read -p "Continue with installation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        ux_error "Installation cancelled"
        return 1
    fi
    
    # Install packages
    ux_info "Running: $INSTALL_CMD$MISSING_PKGS"
    echo ""
    
    if $INSTALL_CMD$MISSING_PKGS; then
        ux_success "Dependencies installed successfully!"
        echo ""
        ux_section "Next Step"
        ux_info "Now you can install Ollama:"
        ux_info "  install-ollama"
        return 0
    else
        ux_error "Failed to install dependencies"
        return 1
    fi
}

# Direct execution guard
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
