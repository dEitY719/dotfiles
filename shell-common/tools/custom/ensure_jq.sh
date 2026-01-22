#!/bin/sh
# shell-common/tools/custom/ensure_jq.sh
# Ensure jq is installed (dependency checker)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

ensure_jq() {
    if command -v jq > /dev/null 2>&1; then
        # jq already installed - silent pass
        return 0
    else
        ux_warning "jq is not installed. Installing..."
        if command -v apt-get > /dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew > /dev/null 2>&1; then
            brew install jq
        elif command -v yum > /dev/null 2>&1; then
            sudo yum install -y jq
        else
            ux_error "Cannot determine package manager. Please install jq manually."
            ux_bullet "Ubuntu/Debian: ${UX_BOLD}sudo apt-get install jq${UX_RESET}"
            ux_bullet "macOS: ${UX_BOLD}brew install jq${UX_RESET}"
            ux_bullet "CentOS/RHEL: ${UX_BOLD}sudo yum install jq${UX_RESET}"
            return 1
        fi

        if command -v jq > /dev/null 2>&1; then
            ux_success "jq installed successfully"
            jq --version
            return 0
        else
            ux_error "Failed to install jq"
            return 1
        fi
    fi
}

# Execute only if run directly (not sourced)
if [ "${0##*/}" = "ensure_jq.sh" ]; then
    ensure_jq "$@"
fi
