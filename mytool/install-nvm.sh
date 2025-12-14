#!/bin/bash

# mytool/install-nvm.sh
# NVM (Node Version Manager) Install Script
# Installs NVM and the latest LTS version of Node.js

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
  NVM & Node.js LTS Install Script
════════════════════════════════════════════════════${reset}

This script will:
  1. Install NVM (Node Version Manager)
  2. Install the latest LTS version of Node.js
  3. Set LTS as the default version

EOF

    if ! confirm "Continue with installation?"; then
        warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install NVM
    # ========================================
    info "Step 1/3: Installing NVM..."

    export NVM_DIR="$HOME/.nvm"
    
    if [ -d "$NVM_DIR" ]; then
        warning "NVM directory ($NVM_DIR) already exists."
        if ! confirm "Do you want to reinstall/update NVM?"; then
             info "Skipping NVM installation."
        else
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            success "NVM installed/updated."
        fi
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        success "NVM installed."
    fi

    # ========================================
    # Step 2: Load NVM
    # ========================================
    info "Step 2/3: Loading NVM..."
    
    # Load NVM for the current session
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
        success "NVM loaded."
    else
        error "Could not find nvm.sh at $NVM_DIR/nvm.sh"
        return 1
    fi

    # ========================================
    # Step 3: Install Node.js LTS
    # ========================================
    info "Step 3/3: Installing Node.js LTS..."

    if confirm "Install latest LTS version of Node.js?"; then
        nvm install --lts
        nvm use --lts
        success "Node.js LTS installed and active."
        
        echo ""
        echo "${bold}Current Versions:${reset}"
        echo "Node: $(node --version)"
        echo "NPM:  $(npm --version)"
    else
        warning "Skipping Node.js LTS installation."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ NVM & Node.js Setup Complete!
════════════════════════════════════════════════════${reset}

${bold}Note:${reset}
  Restart your terminal or run 'source ~/.bashrc' (or ~/.profile)
  to ensure NVM is available in new sessions.

EOF
}

main "$@"
