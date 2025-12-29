#!/bin/bash
# mytool/install-postgresql.sh
# PostgreSQL 서버 설치 스크립트 (대화형)

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "PostgreSQL Server Installer"
    ux_info "This script installs PostgreSQL server on Ubuntu/Debian."
    
    ux_section "Installation Steps"
    ux_numbered 1 "Update package sources."
    ux_numbered 2 "Add official PostgreSQL repository (optional)."
    ux_numbered 3 "Install PostgreSQL server and contrib package."
    ux_numbered 4 "Start and enable the PostgreSQL service."
    ux_numbered 5 "Configure user access (optional)."
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi
    
    # Request sudo privileges upfront
    ux_info "Requesting sudo privileges for the installation..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    # ========================================
    # Step 1: Update package manager
    # ========================================
    ux_step "1/5" "Updating package sources..."
    if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then exit 1; fi

    # ========================================
    # Step 2: Add PostgreSQL Repository
    # ========================================
    ux_step "2/5" "Adding PostgreSQL official repository..."
    if ux_confirm "Add official PostgreSQL repository for the latest version?" "y"; then
        ux_info "Importing PostgreSQL GPG key..."
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg
        
        ux_info "Adding repository source list..."
        local distro_name
        distro_name=$(lsb_release -cs)
        echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt ${distro_name}-pgdg main" | \
            sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
        ux_success "PostgreSQL repository added for '${distro_name}'."
        
        ux_info "Updating apt cache again with the new repository..."
        if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then exit 1; fi
    else
        ux_info "Skipping official repository. The version from default OS repositories will be used."
    fi
    echo ""

    # ========================================
    # Step 3: Update & Install PostgreSQL
    # ========================================
    ux_step "3/5" "Installing PostgreSQL..."
    if ! ux_with_spinner "Installing postgresql and postgresql-contrib" \
        sudo apt-get install -y postgresql postgresql-contrib; then
        ux_error "PostgreSQL installation failed."
        exit 1
    fi

    # ========================================
    # Step 4: Start & Enable Service
    # ========================================
    ux_step "4/5" "Starting and enabling PostgreSQL service..."
    if ! sudo systemctl start postgresql; then
        ux_warning "Failed to start PostgreSQL service. It might be masked or already running."
    else
        ux_success "PostgreSQL service started."
    fi
    if ! sudo systemctl enable postgresql; then
        ux_warning "Failed to enable PostgreSQL service on boot."
    else
        ux_success "PostgreSQL service enabled on boot."
    fi
    echo ""

    # ========================================
    # Step 5: Verify Installation
    # ========================================
    ux_step "5/5" "Verifying installation and configuring user..."
    if ux_confirm "Add current user '$USER' to the 'postgres' group?" "n"; then
        sudo usermod -aG postgres "$USER"
        ux_success "User '$USER' added to 'postgres' group."
        ux_warning "You must log out and log back in, or run 'newgrp postgres' for this to take effect."
    else
        ux_info "User group setup skipped."
    fi

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_header "✅ PostgreSQL Installation Complete!"
    ux_section "Verification"
    ux_info "PostgreSQL Version:"
    sudo -u postgres psql --version || ux_warning "Could not determine version."
    ux_info "Service Status:"
    sudo systemctl status postgresql --no-pager || ux_warning "Could not get service status."

    ux_section "Next Steps"
    ux_numbered 1 "Check server status: ${UX_PRIMARY}psql_server status${UX_RESET}"
    ux_numbered 2 "Add users/databases: ${UX_PRIMARY}psql_add${UX_RESET}"
    ux_numbered 3 "View all helpers: ${UX_PRIMARY}psqlhelp${UX_RESET}"
    echo ""
}

main "$@"
