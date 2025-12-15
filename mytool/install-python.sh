#!/bin/bash

# mytool/install-python.sh
# Pyenv & Python Install Script
# Installs pyenv, dependencies, and the latest stable version of Python.

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
    echo -n "${bold}${blue}${prompt}${reset} (Y/n) "
    read -r response
    [[ -z "$response" || "$response" == "y" || "$response" == "Y" ]]
}

# Main script
main() {
    clear
    cat <<EOF
${bold}${blue}════════════════════════════════════════════════════
  Pyenv & Python Install Script
════════════════════════════════════════════════════${reset}

This script will:
  1. Install build dependencies for Python
  2. Install Pyenv (Python Version Manager)
  3. Install the latest stable version of Python (3.12.3)
  4. Set it as the global default version

EOF

    if ! confirm "Continue with installation?"; then
        warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install build dependencies
    # ========================================
    info "Step 1/4: Installing Python build dependencies (requires sudo)..."
    if command -v apt-get >/dev/null; then
        sudo apt-get update
        sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
        success "Build dependencies installed."
    else
        warning "Could not find apt-get. Skipping dependency installation. Please install them manually."
    fi

    # ========================================
    # Step 2: Install Pyenv
    # ========================================
    info "Step 2/4: Installing Pyenv..."
    if [ -d "$HOME/.pyenv" ]; then
        warning "Pyenv directory ($HOME/.pyenv) already exists."
        if confirm "Do you want to update pyenv?"; then
            pyenv update
            success "Pyenv updated."
        else
            info "Skipping pyenv installation/update."
        fi
    else
        curl https://pyenv.run | bash
        success "Pyenv installed."
    fi

    # ========================================
    # Step 3: Load Pyenv
    # ========================================
    info "Step 3/4: Loading Pyenv..."
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
    success "Pyenv loaded for the current session."

    # ========================================
    # Step 4: Install Python
    # ========================================
    info "Step 4/4: Installing Python 3.12.3..."
    PYTHON_VERSION="3.12.3"
    if confirm "Install Python $PYTHON_VERSION and set as global?"; then
        pyenv install "$PYTHON_VERSION" --skip-existing
        pyenv global "$PYTHON_VERSION"
        success "Python $PYTHON_VERSION installed and set as global."

        echo ""
        echo "${bold}Current Versions:${reset}"
        echo "Python: $(python --version)"
        echo "Pip:    $(pip --version | awk '{print $1, $2}')"
    else
        warning "Skipping Python installation."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    cat <<EOF
${bold}${green}════════════════════════════════════════════════════
  ✅ Pyenv & Python Setup Complete!
════════════════════════════════════════════════════${reset}

${bold}Note:${reset}
  Restart your terminal or run 'source ~/.bashrc' (or ~/.profile)
  to ensure Pyenv and Python are available in new sessions.

EOF
}

main "$@"
