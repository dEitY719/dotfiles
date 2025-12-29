#!/bin/bash
# This script sets up the en_US.UTF-8 locale to resolve "manpath: can't set the locale" errors.

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

main() {
    clear
    ux_header "System Locale Setter (en_US.UTF-8)"
    ux_info "This script generates and sets the system locale to en_US.UTF-8."
    ux_warning "This can resolve errors like 'manpath: can't set the locale'."
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Operation cancelled."
        exit 0
    fi

    # Request sudo privileges
    ux_info "Requesting sudo privileges..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &> /dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    # Step 1: Generate locale
    ux_step "1/2" "Generating en_US.UTF-8 locale..."
    if ! ux_with_spinner "Running locale-gen" sudo locale-gen en_US.UTF-8; then
        exit 1
    fi

    # Step 2: Update locale
    ux_step "2/2" "Updating default system locale..."
    if ! ux_with_spinner "Running update-locale" sudo update-locale LANG=en_US.UTF-8; then
        exit 1
    fi

    # Clean up sudo keep-alive
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # Completion
    echo ""
    ux_header "✅ Locale setup complete!"
    ux_success "System locale has been set to en_US.UTF-8."
    ux_warning "Please restart your terminal or run 'source ~/.bashrc' to apply the changes."
    echo ""
}

main "$@"
