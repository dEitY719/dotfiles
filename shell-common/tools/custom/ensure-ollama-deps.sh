#!/bin/bash
# shell-common/tools/custom/ensure-ollama-deps.sh
# Ollama Dependency Installer
# Single Responsibility: Install system dependencies required for Ollama
# Does NOT install Ollama itself - that's install_ollama.sh's job

set -e

# PATH executable since #2195 (~/.local/bin/ensure-ollama-deps via config/symlinks.conf).
# Resolve the ~/.local/bin symlink so init.sh is found next to the real file.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

ensure_ollama_deps_help() {
    ux_usage "ensure-ollama-deps" "" "Install the system packages Ollama needs (zstd, curl)"
    ux_bullet "Linux/WSL only: apt-get, dnf or pacman via sudo"
    ux_bullet "Does not install Ollama itself: run install-ollama next"
}

main() {
    case "${1:-}" in -h | --help) ensure_ollama_deps_help; return 0 ;; esac
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
    
    # shellcheck disable=SC2086  # reason: both hold space-separated words that must split into argv
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
