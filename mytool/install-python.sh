#!/bin/bash
# mytool/install-python.sh
# Pyenv & Python Install Script
# Installs pyenv, dependencies, and a specific version of Python.

set -e

# Source the UX library
# shellcheck source=../bash/ux_lib/ux_lib.bash
source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

main() {
    clear
    ux_header "Pyenv & Python Installer"
    ux_info "This script installs pyenv, Python build dependencies, and a recent Python version."
    
    local python_version="3.12.3"
    ux_section "Installation Steps"
    ux_numbered 1 "Install Python build dependencies (requires sudo)."
    ux_numbered 2 "Install pyenv (Python Version Manager) via Git."
    ux_numbered 3 "Load pyenv into the current session."
    ux_numbered 4 "Install Python ${python_version} and set as global default."
    echo ""
    ux_warning "This script requires sudo privileges for dependency installation."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi
    
    # Request sudo privileges upfront
    ux_info "Requesting sudo privileges for installing dependencies..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    # ========================================
    # Step 1: Install build dependencies
    # ========================================
    ux_step "1/4" "Installing Python build dependencies..."
    if command -v apt-get >/dev/null; then
        if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then exit 1; fi
        
        local dependencies=(
            make build-essential libssl-dev zlib1g-dev libbz2-dev 
            libreadline-dev libsqlite3-dev wget curl llvm libncursesw5-dev 
            xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
        )
        if ! ux_with_spinner "Installing build dependencies" sudo apt-get install -y -qq "${dependencies[@]}"; then
            ux_error "Failed to install build dependencies."
            exit 1
        fi
    else
        ux_warning "apt-get not found. Skipping dependency installation."
        ux_info "Please install the Python build dependencies for your system manually."
    fi
    echo ""

    # ========================================
    # Step 2: Install Pyenv
    # ========================================
    ux_step "2/4" "Installing pyenv..."
    if [ -d "$HOME/.pyenv" ]; then
        ux_warning "pyenv directory ($HOME/.pyenv) already exists."
        if ux_confirm "Do you want to update pyenv by pulling the latest changes from Git?" "y"; then
            ux_info "Updating pyenv..."
            (cd "$HOME/.pyenv" && git pull)
            ux_success "pyenv updated."
        else
            ux_info "Skipping pyenv update."
        fi
    else
        ux_info "Cloning pyenv from GitHub..."
        git clone https://github.com/pyenv/pyenv.git ~/.pyenv
        ux_success "pyenv installed."
    fi
    echo ""

    # ========================================
    # Step 3: Load Pyenv
    # ========================================
    ux_step "3/4" "Loading pyenv..."
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    if ! command -v pyenv &>/dev/null; then
        ux_error "pyenv command not found after installation."
        exit 1
    fi
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
    ux_success "pyenv loaded for the current session."
    echo ""

    # ========================================
    # Step 4: Install Python
    # ========================================
    ux_step "4/4" "Installing Python ${python_version}..."
    if ux_confirm "Install Python ${python_version} and set as global default?" "y"; then
        ux_info "Installing Python ${python_version} with pyenv (this may take a while)..."
        # pyenv install has its own detailed output, no spinner needed.
        pyenv install "$python_version" --skip-existing
        pyenv global "$python_version"
        ux_success "Python ${python_version} installed and set as global."

        echo ""
        ux_section "Current Versions"
        py_version=$(python --version 2>&1)
        pip_version=$(pip --version 2>&1 | awk '{print $1, $2}')
        ux_table_header "Component" "Version"
        ux_table_row "Python" "$py_version"
        ux_table_row "Pip" "$pip_version"
    else
        ux_info "Skipping Python installation."
    fi

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Pyenv & Python Setup Complete!"
    ux_warning "You must restart your terminal or run 'source ~/.bashrc' to make pyenv available in new sessions."
    echo ""
}

main "$@"
