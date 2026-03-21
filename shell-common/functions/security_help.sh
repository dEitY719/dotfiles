#!/bin/sh
# shell-common/functions/security_help.sh
# CA Certificate setup help and utilities

# Load UX library (unified library at shell-common/tools/ux_lib/)
if ! type ux_header >/dev/null 2>&1; then
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
fi

crt_help() {
    ux_header "CA Certificate Setup Guide"

    ux_section "Overview"
    ux_bullet "Manages CA certificates for npm, Node.js, and Python"
    ux_bullet "Supports custom certificates (company proxy) and system CA bundles"
    ux_bullet "Configuration stored in: shell-common/env/security.local.sh"

    ux_section "Two Options"
    ux_bullet "Option 1: Custom Certificate (External Company PC - VPN)"
    ux_bullet " • Certificate path: ${UX_MUTED}/usr/local/share/ca-certificates/samsungsemi-prx.com.crt${UX_RESET}"
    ux_bullet " • Install with: ${UX_SUCCESS}crtsetup${UX_RESET}"
    ux_bullet "Option 2: System CA Bundle (Internal Company PC)"
    ux_bullet " • Certificate path: ${UX_MUTED}/etc/ssl/certs/ca-certificates.crt${UX_RESET}"
    ux_bullet " • Already system default, no setup needed"

    ux_section "Setup Command"
    ux_table_row "crtsetup" "Interactive CA certificate setup script"

    ux_section "Environment Variables"
    ux_table_row "NODE_EXTRA_CA_CERTS" "Used by Node.js/npm for certificate validation"
    ux_table_row "REQUESTS_CA_BUNDLE" "Used by Python for certificate validation"

    ux_section "Configuration File"
    ux_info "Location: ${UX_BOLD}shell-common/env/security.local.sh${UX_RESET}"

    ux_section "Related Commands"
    ux_table_row "npm-help" "NPM package manager commands and setup"
    ux_table_row "security.sh" "Security environment variable configuration"
    ux_table_row "setup.sh" "Initial environment-specific setup"
}

alias crt-help='crt_help'
