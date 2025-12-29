#!/bin/bash
# mytool/install-zsh.sh
# Zsh Install Script
# Installs zsh shell with optional oh-my-zsh framework and plugins

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "Zsh Shell Installer"
    ux_info "This script installs zsh shell alongside bash with optional enhancements."

    ux_section "Installation Options"
    ux_numbered 1 "Install zsh shell package"
    ux_numbered 2 "Configure zsh with dotfiles integration"
    ux_numbered 3 "Optional: Install oh-my-zsh framework"
    ux_numbered 4 "Optional: Install popular zsh plugins"
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Install Zsh Package
    # ========================================
    ux_step "1/4" "Installing zsh package..."

    if command -v zsh &> /dev/null; then
        ux_warning "zsh is already installed."
        zsh_version=$(zsh --version)
        ux_info "Current version: $zsh_version"
        if ! ux_confirm "Do you want to reinstall or upgrade zsh?" "n"; then
            ux_info "Skipping zsh installation."
        else
            ux_info "Running 'sudo apt-get install --only-upgrade zsh'..."
            sudo apt-get update && sudo apt-get install --only-upgrade zsh
            ux_success "zsh upgraded."
        fi
    else
        ux_info "Running 'sudo apt-get install zsh'..."
        sudo apt-get update && sudo apt-get install -y zsh
        ux_success "zsh installed successfully."
    fi
    echo ""

    # ========================================
    # Step 2: Create Zsh Config Directory
    # ========================================
    ux_step "2/4" "Setting up zsh configuration..."

    local zsh_config_dir="${HOME}/.zshrc.d"
    if [ ! -d "$zsh_config_dir" ]; then
        mkdir -p "$zsh_config_dir"
        ux_success "Created zsh config directory: $zsh_config_dir"
    else
        ux_info "zsh config directory already exists: $zsh_config_dir"
    fi
    echo ""

    # ========================================
    # Step 3: Optional Oh-My-Zsh Installation
    # ========================================
    ux_step "3/4" "Setting up oh-my-zsh (optional)..."

    local omz_dir="${HOME}/.oh-my-zsh"

    if [ -d "$omz_dir" ]; then
        ux_warning "oh-my-zsh is already installed."
        if ux_confirm "Do you want to update oh-my-zsh?" "n"; then
            ux_info "Updating oh-my-zsh..."
            cd "$omz_dir" && git pull
            ux_success "oh-my-zsh updated."
        fi
    else
        if ux_confirm "Install oh-my-zsh framework for enhanced zsh experience?" "y"; then
            ux_info "Installing oh-my-zsh..."
            local omz_install_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

            # Download and run oh-my-zsh installer
            # The installer will handle creating .zshrc
            sh -c "$(curl -fsSL $omz_install_url)" "" --keep-zshrc
            ux_success "oh-my-zsh installed successfully."
        else
            ux_info "Skipping oh-my-zsh installation."
        fi
    fi
    echo ""

    # ========================================
    # Step 4: Install Popular Zsh Plugins
    # ========================================
    ux_step "4/4" "Setting up zsh plugins (optional)..."

    if ux_confirm "Install popular zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)?" "y"; then
        ux_info "Installing zsh plugins..."

        local plugins_dir="${HOME}/.oh-my-zsh/custom/plugins"

        # zsh-autosuggestions
        if [ -d "$plugins_dir/zsh-autosuggestions" ]; then
            ux_info "zsh-autosuggestions already installed."
        else
            ux_info "Installing zsh-autosuggestions..."
            git clone https://github.com/zsh-users/zsh-autosuggestions "$plugins_dir/zsh-autosuggestions"
            ux_success "zsh-autosuggestions installed."
        fi

        # zsh-syntax-highlighting
        if [ -d "$plugins_dir/zsh-syntax-highlighting" ]; then
            ux_info "zsh-syntax-highlighting already installed."
        else
            ux_info "Installing zsh-syntax-highlighting..."
            git clone https://github.com/zsh-users/zsh-syntax-highlighting "$plugins_dir/zsh-syntax-highlighting"
            ux_success "zsh-syntax-highlighting installed."
        fi

        ux_warning "Note: Add these plugins to 'plugins=(...)' in your ~/.zshrc"
        echo "  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
    else
        ux_info "Skipping plugin installation."
    fi
    echo ""

    # ========================================
    # Step 5: Show Configuration Tips
    # ========================================
    ux_section "Configuration Tips"
    ux_bullet "Main config: ${UX_BOLD}~/.zshrc${UX_RESET}"
    ux_bullet "Config directory: ${UX_BOLD}~/.zshrc.d/${UX_RESET}"
    ux_bullet "Switch to zsh: ${UX_BOLD}zsh${UX_RESET}"
    ux_bullet "Switch to bash: ${UX_BOLD}bash${UX_RESET}"
    ux_bullet "Set zsh as default: ${UX_BOLD}chsh -s $(which zsh)${UX_RESET}"
    echo ""

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Zsh Setup Complete!"
    ux_info "You can now use both bash and zsh. Switch shells with: ${UX_BOLD}zsh${UX_RESET} or ${UX_BOLD}bash${UX_RESET}"
    ux_warning "To make zsh your default shell, run: ${UX_BOLD}chsh -s \$(which zsh)${UX_RESET}"
    echo ""
}

main "$@"
