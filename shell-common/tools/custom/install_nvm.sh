#!/bin/bash
# mytool/install_nvm.sh
# NVM (Node Version Manager) Install Script
# Installs NVM and the latest LTS version of Node.js

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "NVM & Node.js LTS Installer"
    ux_info "This script installs NVM (Node Version Manager) and the latest LTS Node.js version."

    ux_section "Installation Steps"
    ux_numbered 1 "Download and run the NVM installation script."
    ux_numbered 2 "Load NVM into the current session."
    ux_numbered 3 "Install the latest LTS (Long-Term Support) version of Node.js."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install NVM
    # ========================================
    ux_step "1/3" "Installing NVM..."
    export NVM_DIR="$HOME/.nvm"
    local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh"
    
    if [ -d "$NVM_DIR" ]; then
        ux_warning "NVM directory ($NVM_DIR) already exists."
        if ! ux_confirm "Do you want to run the installer again to update NVM?" "n"; then
             ux_info "Skipping NVM installation."
        else
            ux_info "Running NVM installer from ${nvm_install_url}..."
            # The installer has its own output, so we don't use a spinner
            curl -o- "$nvm_install_url" | bash
            ux_success "NVM install/update script finished."
        fi
    else
        ux_info "Running NVM installer from ${nvm_install_url}..."
        curl -o- "$nvm_install_url" | bash
        ux_success "NVM install script finished."
    fi
    echo ""

    # ========================================
    # Step 2: Load NVM
    # ========================================
    ux_step "2/3" "Loading NVM..."
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        ux_success "NVM loaded for the current session."
    else
        ux_error "Could not find nvm.sh to load. Installation may have failed."
        exit 1
    fi
    echo ""

    # ========================================
    # Step 3: Install Node.js LTS
    # ========================================
    ux_step "3/3" "Installing Node.js LTS..."
    if ux_confirm "Install the latest LTS version of Node.js and set it as default?" "y"; then
        ux_info "Running 'nvm install --lts'..."
        # nvm also has its own rich output
        nvm install --lts
        ux_info "Setting LTS as the default version for new shells..."
        nvm alias default 'lts/*'
        ux_success "Node.js LTS installed and set as default."
        
        echo ""
        ux_section "Current Versions"
        nvm_version=$(nvm --version)
        node_version=$(node --version)
        npm_version=$(npm --version)
        ux_table_header "Component" "Version"
        ux_table_row "NVM" "$nvm_version"
        ux_table_row "Node.js" "$node_version"
        ux_table_row "npm" "$npm_version"
    else
        ux_info "Skipping Node.js LTS installation."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ NVM & Node.js Setup Complete!"
    ux_warning "You must restart your terminal or run 'source ~/.bashrc' for NVM to be available in new sessions."
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
