#!/bin/bash
# shell-common/functions/securityhelp.sh
# CA Certificate setup help and utilities

# Load UX library (unified library at shell-common/tools/ux_lib/)
if ! type ux_header >/dev/null 2>&1; then
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
fi

# ═══════════════════════════════════════════════════════════════
# CA Certificate Setup Help
# ═══════════════════════════════════════════════════════════════

crt_help() {
    ux_header "CA Certificate Setup Guide"

    ux_section "Overview"
    ux_bullet "Manages CA certificates for npm, Node.js, and Python"
    ux_bullet "Supports custom certificates (company proxy) and system CA bundles"
    ux_bullet "Configuration stored in: shell-common/env/security.local.sh"
    echo ""

    ux_section "Quick Start"
    echo "1. Run setup.sh to initialize your environment:"
    echo "   ${UX_SUCCESS}./setup.sh${UX_RESET}"
    echo ""
    echo "2. Select your environment (Public/Internal/External PC)"
    echo ""
    echo "3. For external company PC with custom certificate:"
    echo "   ${UX_SUCCESS}crtsetup${UX_RESET}"
    echo ""

    ux_section "Two Options"
    echo ""
    ux_bullet "Option 1: Custom Certificate (External Company PC - VPN)"
    echo "   • Use when connecting via company VPN"
    echo "   • Certificate path: ${UX_MUTED}/usr/local/share/ca-certificates/samsungsemi-prx.com.crt${UX_RESET}"
    echo "   • Install with: ${UX_SUCCESS}crtsetup${UX_RESET}"
    echo ""

    ux_bullet "Option 2: System CA Bundle (Internal Company PC)"
    echo "   • Use when connecting directly from company network"
    echo "   • Certificate path: ${UX_MUTED}/etc/ssl/certs/ca-certificates.crt${UX_RESET}"
    echo "   • Already system default, no setup needed"
    echo ""

    ux_section "Setup Command"
    ux_table_row "crtsetup" "Interactive CA certificate setup script"
    echo ""
    ux_info "This command will:"
    ux_bullet "Check current certificate status"
    ux_bullet "Obtain certificate file (from local file or manual setup)"
    ux_bullet "Install certificate to system"
    ux_bullet "Update system certificate store"
    ux_bullet "Verify installation"
    echo ""

    ux_section "Environment Variables"
    ux_table_row "NODE_EXTRA_CA_CERTS" "Used by Node.js/npm for certificate validation"
    ux_table_row "REQUESTS_CA_BUNDLE" "Used by Python for certificate validation"
    echo ""

    ux_section "Configuration File"
    echo "Location: ${UX_BOLD}shell-common/env/security.local.sh${UX_RESET}"
    echo ""
    ux_info "To configure:"
    echo "  1. Check current environment: ${UX_SUCCESS}./setup.sh${UX_RESET}"
    echo "  2. Edit file: ${UX_SUCCESS}vim shell-common/env/security.local.sh${UX_RESET}"
    echo "  3. Uncomment one CA_CERT option (choose based on your environment)"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "Certificate not found: Run ${UX_SUCCESS}crtsetup${UX_RESET} to install"
    ux_bullet "NODE_EXTRA_CA_CERTS not set: Source ~/.bashrc (${UX_SUCCESS}source ~/.bashrc${UX_RESET})"
    ux_bullet "npm fails with certificate error: Check ${UX_SUCCESS}echo \$NODE_EXTRA_CA_CERTS${UX_RESET}}"
    ux_bullet "Need to remove certificate: ${UX_SUCCESS}sudo rm /usr/local/share/ca-certificates/<cert>.crt${UX_RESET}}"
    echo ""

    ux_section "Related Commands"
    ux_table_row "npm-help" "NPM package manager commands and setup"
    ux_table_row "security.sh" "Security environment variable configuration"
    ux_table_row "setup.sh" "Initial environment-specific setup"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Help Registration
# ═══════════════════════════════════════════════════════════════

# Note: HELP_DESCRIPTIONS registration is handled by myhelp.sh
# which loads before this file and properly initializes the array
# in a shell-independent way

# Alias for crt-help format (using dash instead of underscore)
alias crt-help='crt_help'
