#!/bin/bash

# mytool/install-claude.sh
# Claude Code CLI Install Script
# Installs the @anthropic-ai/claude-code global npm package.

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
  Claude Code CLI Install Script
════════════════════════════════════════════════════${reset}

This script will:
  1. Check for NVM (Node Version Manager) installation.
  2. Install the '@anthropic-ai/claude-code' global npm package.

EOF

    if ! confirm "Continue with installation?"; then
        warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check for NVM
    # ========================================
    info "Step 1/2: Checking for NVM (Node Version Manager)..."
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        \. "$HOME/.nvm/nvm.sh" # Load nvm
        success "NVM is installed and loaded."
    else
        error "NVM is not installed or not loaded. Please install NVM first."
        info "You can install NVM using 'nvm install' or by running '$HOME/dotfiles/mytool/install-nvm.sh'."
        exit 1
    fi

    # ========================================
    # Step 2: Install Claude Code CLI
    # ========================================
    info "Step 2/2: Installing '@anthropic-ai/claude-code' globally..."
    if command -v claude &>/dev/null; then
        warning "Claude Code CLI appears to be already installed."
        if ! confirm "Do you want to reinstall/update it?"; then
            info "Skipping Claude Code CLI installation."
            exit 0
        fi
    fi

    npm install -g @anthropic-ai/claude-code
    success "Claude Code CLI installed/updated."

    echo ""
    echo "${bold}Verification:${reset}"
    if command -v claude &>/dev/null; then
        claude --version
    else
        warning "Claude command not found after installation. Please check your PATH."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Claude Code CLI Setup Complete!
════════════════════════════════════════════════════${reset}

${bold}Note:${reset}
  If 'claude --version' above failed, please restart your terminal or run
  'source ~/.bashrc' (or ~/.profile) to ensure your PATH is updated.

EOF
}

main "$@"
