#!/bin/bash
# mytool/enable-docker.sh
# Docker 서비스 자동 시작 설정 (systemd) - 대화형

set -e

# Source the UX library
# shellcheck source=../bash/ux_lib/ux_lib.bash
source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

# Main script
main() {
    clear
    ux_header "Docker Service Auto-Start Setup"
    ux_info "This script enables the Docker service to start automatically on boot (with systemd)."

    ux_section "Setup Process"
    ux_numbered 1 "Start the Docker service now."
    ux_numbered 2 "Enable the Docker service to start on boot."
    ux_numbered 3 "Verify the service status."
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Setup cancelled."
        exit 0
    fi

    # Check Docker installation
    ux_info "Checking Docker installation status..."
    if ! ux_require "docker"; then
        ux_error "Docker is not installed. Please run 'dinstall' first."
        exit 1
    fi
    ux_success "Docker is installed."
    echo ""

    # Step 1: Start Docker
    ux_step "1/3" "Starting Docker service"
    if ux_confirm "Start the Docker service now?" "y"; then
        if sudo systemctl start docker; then
            ux_success "Docker service started successfully."
        else
            ux_error "Failed to start Docker service."
            return 1
        fi
    else
        ux_info "Step 1 skipped by user."
    fi
    echo ""

    # Step 2: Enable Docker
    ux_step "2/3" "Enabling Docker auto-start"
    if ux_confirm "Enable Docker to start automatically on boot?" "y"; then
        if sudo systemctl enable docker; then
            ux_success "Docker auto-start enabled successfully."
        else
            ux_error "Failed to enable Docker auto-start."
            return 1
        fi
    else
        ux_info "Step 2 skipped by user."
    fi
    echo ""

    # Step 3: Verify Status
    ux_step "3/3" "Verifying Docker service status"
    if ux_confirm "Check Docker service status now?" "y"; then
        echo ""
        ux_section "Docker Service Status"
        if sudo systemctl status docker --no-pager; then
            echo ""
            ux_success "Docker service appears to be running correctly."
        else
            ux_warning "Could not confirm Docker service status."
        fi
    else
        ux_info "Step 3 skipped by user."
    fi

    # Completion
    echo ""
    ux_header "✅ Docker Auto-Start Setup Complete!"
    ux_section "Next Steps"
    ux_numbered 1 "Restart WSL: ${UX_PRIMARY}wsl --shutdown${UX_RESET}"
    ux_numbered 2 "After restarting WSL, check if Docker is running: ${UX_PRIMARY}docker ps${UX_RESET}"
    echo ""

    ux_section "Verification Commands"
    ux_table_header "Description" "Command"
    ux_table_row "Service Status" "sudo systemctl status docker"
    ux_table_row "Auto-start Status" "sudo systemctl is-enabled docker"
    echo ""

    ux_section "More Commands"
    ux_info "For more Docker commands, run: ${UX_PRIMARY}dockerhelp${UX_RESET}"
    echo ""
}

main "$@"
