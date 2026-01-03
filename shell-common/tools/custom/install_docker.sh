#!/bin/bash
# mytool/install_docker.sh
# WSL Docker 설치 스크립트 (대화형)

set -e

# Initialize common tools environment (loads unified UX library via init.sh)
# Path: shell-common/tools/custom/install_docker.sh -> ../ux_lib/ux_lib.sh
source "$(dirname "$0")/init.sh" || exit 1

# Main script
main() {
    clear
    ux_header "Docker Installer for WSL/Ubuntu"
    ux_info "This script installs Docker Engine and Docker Compose."

    ux_section "Installation Steps"
    ux_numbered 1 "Update package sources"
    ux_numbered 2 "Install dependencies (curl, gnupg, etc.)"
    ux_numbered 3 "Add Docker's official GPG key"
    ux_numbered 4 "Set up the Docker repository"
    ux_numbered 5 "Install Docker Engine and Compose"
    ux_numbered 6 "Configure sudo-less Docker access (optional)"
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    # Prompt for sudo password upfront and keep the session alive
    ux_info "Requesting sudo privileges for the installation..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    # Keep the sudo session alive in the background
    while true; do sudo -n true; sleep 60; kill -0 "$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid"' EXIT
    
    ux_success "Sudo privileges acquired."
    echo ""

    # ========================================
    # Step 1: Update package manager
    # ========================================
    ux_step "1/6" "Updating package manager sources..."
    if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then
        exit 1
    fi
    
    # ========================================
    # Step 2: Install Docker dependencies
    # ========================================
    ux_step "2/6" "Installing Docker dependencies..."
    if ! ux_with_spinner "Installing dependencies" sudo apt-get install -y -qq ca-certificates curl; then
         exit 1
    fi

    # ========================================
    # Step 3: Add Docker's official GPG key
    # ========================================
    ux_step "3/6" "Adding Docker's official GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    ux_success "Docker GPG key added successfully."

    # ========================================
    # Step 4: Add Docker repository
    # ========================================
    ux_step "4/6" "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    ux_success "Docker repository added successfully."

    # ========================================
    # Step 5: Update & Install Docker
    # ========================================
    ux_step "5/6" "Updating apt and installing Docker..."
    if ! ux_with_spinner "Updating apt cache again" sudo apt-get update -qq; then
        exit 1
    fi
    if ! ux_with_spinner "Installing Docker packages" sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        exit 1
    fi

    # ========================================
    # Step 6: Post-installation (optional)
    # ========================================
    ux_step "6/6" "Configuring sudo-less Docker access..."
    if ux_confirm "Add current user '$USER' to the 'docker' group for sudo-less access?" "y"; then
        sudo groupadd -f docker
        if sudo usermod -aG docker "$USER"; then
            ux_success "User '$USER' added to 'docker' group."
            ux_warning "You must log out and log back in, or run 'newgrp docker' for this to take effect."
        else
            ux_error "Failed to add user to 'docker' group."
        fi
    else
        ux_info "Sudo-less access setup skipped."
    fi

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ Docker Installation Complete!"
    ux_section "Verification"
    if command -v docker &>/dev/null; then
        ux_info "Docker Version:"
        docker --version
        ux_info "Docker Compose Version:"
        docker compose version
    else
        ux_error "Docker command not found after installation."
    fi
    
    ux_section "Next Steps"
    ux_numbered 1 "If you added user to docker group, restart WSL: ${UX_PRIMARY}wsl --shutdown${UX_RESET}"
    ux_numbered 2 "Test the installation: ${UX_PRIMARY}docker run hello-world${UX_RESET}"
    echo ""
    ux_info "For more Docker commands, run: ${UX_PRIMARY}docker-help${UX_RESET}"
    echo ""
    
    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT
}

main "$@"
