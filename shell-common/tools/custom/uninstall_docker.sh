#!/bin/bash
# mytool/uninstall_docker.sh
# WSL Docker 제거 스크립트 (대화형)

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

# Main script
main() {
    clear
    ux_header "Docker Uninstaller"
    ux_info "This script uninstalls Docker Engine, CLI, and Compose."
    echo ""
    ux_warning "This is a destructive action that will remove Docker packages from your system."
    ux_error "A full purge will also delete all images, containers, volumes, and networks."
    echo ""

    if ! ux_confirm "Are you sure you want to proceed with Docker uninstallation?" "n"; then
        ux_warning "Uninstallation cancelled."
        exit 0
    fi

    # Request sudo privileges
    ux_info "Requesting sudo privileges for uninstallation..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    local docker_packages=(
        docker-ce docker-ce-cli containerd.io 
        docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    )

    # ========================================
    # Step 1: Uninstall Docker packages
    # ========================================
    ux_step "1/3" "Uninstalling Docker packages..."
    if ux_confirm "Completely purge all Docker data (images, volumes, configs)?" "n"; then
        ux_warning "PURGING all Docker data..."
        if ! ux_with_spinner "Purging packages and data" sudo apt-get -y purge "${docker_packages[@]}"; then
            ux_warning "Could not purge all packages. They may not have been installed."
        fi
        ux_info "Also removing docker data directories..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        ux_success "Docker data directories removed."
    else
        ux_info "Performing a standard removal of Docker packages (keeping data)..."
        if ! ux_with_spinner "Removing apt packages" sudo apt-get -y remove "${docker_packages[@]}"; then
            ux_warning "Could not remove all docker packages. They may not have been installed."
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Remove Docker repository and GPG key
    # ========================================
    ux_step "2/3" "Removing Docker repository..."
    if ux_confirm "Remove the Docker APT repository and GPG key?" "y"; then
        [ -f /etc/apt/sources.list.d/docker.list ] && sudo rm -f /etc/apt/sources.list.d/docker.list && ux_success "Removed docker.list."
        [ -f /etc/apt/keyrings/docker.gpg ] && sudo rm -f /etc/apt/keyrings/docker.gpg && ux_success "Removed docker.gpg."
        ux_with_spinner "Updating apt cache" sudo apt-get update -qq
    else
        ux_info "Skipped removing Docker repository."
    fi
    echo ""

    # ========================================
    # Step 3: Remove docker group
    # ========================================
    ux_step "3/3" "Removing docker group..."
    if getent group docker > /dev/null; then
        if ux_confirm "Remove the 'docker' user group?" "n"; then
            if sudo groupdel docker; then
                ux_success "Removed 'docker' group."
            else
                ux_warning "Failed to remove 'docker' group. Is any user still a member?"
            fi
        fi
    fi
    echo ""

    # Clean up
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    ux_header "✅ Docker Uninstallation Complete!"
    if command -v docker &> /dev/null; then
        ux_warning "The 'docker' command still exists. You may need to check your PATH or restart your shell."
    else
        ux_success "The 'docker' command has been successfully removed."
    fi
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
