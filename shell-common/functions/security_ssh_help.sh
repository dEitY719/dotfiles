#!/bin/sh
# shell-common/functions/security_ssh_help.sh
# Bundle: security, SSL, and SSH help functions

# --- crt_help (from security_help.sh) ---

# Load UX library (unified library at shell-common/tools/ux_lib/)
if ! type ux_header >/dev/null 2>&1; then
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
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

# --- ssh_help (from ssh_help.sh) ---

ssh_help() {
    ux_header "SSH / SCP Commands"

    ux_section "SSH - Connect & Run"
    ux_table_row "ssh <host>" "ssh ssai-dev" "Connect to server"
    ux_table_row "ssh <host> <cmd>" "ssh ssai-dev 'ls /home'" "Run remote command"

    ux_section "SCP - File Transfer"
    ux_table_row "pull" "scp <host>:<src> <dst>" "Download from server"
    ux_table_row "push" "scp <src> <host>:<dst>" "Upload to server"

    ux_section "Registered Hosts (~/.ssh/config)"
    if [ -f "${HOME}/.ssh/config" ]; then
        set -f  # Disable glob expansion to prevent Host * from expanding
        while IFS= read -r line; do
            # Trim leading whitespace
            line_trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
            case "$line_trimmed" in
                \#* | "")  continue ;;  # Skip comments and empty lines
                Host\ \*)  continue ;;  # Skip wildcard Host *
                Host\ *)
                    hosts="${line_trimmed#Host }"
                    for host in $hosts; do
                        ux_bullet "$host"
                    done
                    ;;
            esac
        done < "${HOME}/.ssh/config"
        set +f  # Re-enable glob expansion
    else
        ux_info "~/.ssh/config not found. Run ./setup.sh to create symlink."
    fi

    ux_section "Config"
    ux_table_row "config file" "~/.ssh/config → dotfiles/ssh/config" "Managed by dotfiles"
}

alias ssh-help='ssh_help'

# --- ssl_help (from ssl_help.sh) ---

ssl_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "SSL Certificate Configuration & Diagnostics"
    else
        echo "=== SSL Certificate Configuration & Diagnostics ==="
    fi

    if type ux_section >/dev/null 2>&1; then
        ux_section "Current SSL Certificate Status"

        if [ -n "$SSL_CERT_FILE" ]; then
            ux_success "SSL_CERT_FILE: $SSL_CERT_FILE"
            if [ -f "$SSL_CERT_FILE" ]; then
                ux_success "  ✓ File exists and is readable"
            else
                ux_warning "  ✗ File NOT found (may need to be installed)"
            fi
        else
            ux_warning "SSL_CERT_FILE: [NOT SET]"
            ux_info "  This is normal for public/home environments"
        fi

        if [ -n "$REQUESTS_CA_BUNDLE" ]; then
            ux_success "REQUESTS_CA_BUNDLE: $REQUESTS_CA_BUNDLE (Python requests)"
        else
            ux_info "REQUESTS_CA_BUNDLE: [NOT SET]"
        fi

        if [ -n "$NODE_EXTRA_CA_CERTS" ]; then
            ux_success "NODE_EXTRA_CA_CERTS: $NODE_EXTRA_CA_CERTS (Node.js)"
        else
            ux_info "NODE_EXTRA_CA_CERTS: [NOT SET]"
        fi

        ux_section "Quick Commands"
        ux_bullet "echo \$SSL_CERT_FILE                  Show SSL certificate file"
        ux_bullet "echo \$REQUESTS_CA_BUNDLE             Show Python requests CA bundle"
        ux_bullet "env | grep -i cert                   Show all certificate vars"

        ux_section "Security Configuration Files"
        local security_local="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/env/security.local.sh"
        if [ -f "$security_local" ]; then
            ux_success "security.local.sh: exists"
            ux_bullet "Location: $security_local"
        else
            ux_info "security.local.sh: not configured (public environment)"
        fi

        ux_section "Certificate Paths by Environment"
        ux_bullet "Internal PC:  /usr/share/ca-certificates/extra/McAfee_Certificate.crt"
        ux_bullet "External PC:  /usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
        ux_bullet "System CA:    /etc/ssl/certs/ca-certificates.crt"

        ux_section "Tools That Use SSL_CERT_FILE"
        ux_bullet "curl                 - Web requests and downloads"
        ux_bullet "wget                 - File downloads"
        ux_bullet "git                  - Git operations (HTTPS)"
        ux_bullet "python (requests)    - HTTP library"
        ux_bullet "npm                  - Node.js package manager"

        ux_section "Important Notes"
        ux_warning "Different variables for different tools:"
        ux_info "  - SSL_CERT_FILE:        curl, wget, git"
        ux_info "  - REQUESTS_CA_BUNDLE:   Python requests"
        ux_info "  - NODE_EXTRA_CA_CERTS:  Node.js"

    else
        # Fallback for minimal shells without UX library
        echo ""
        echo "Current SSL_CERT_FILE: ${SSL_CERT_FILE:-[NOT SET]}"
        echo "Current REQUESTS_CA_BUNDLE: ${REQUESTS_CA_BUNDLE:-[NOT SET]}"
        echo ""
        echo "Quick commands:"
        echo "  echo \$SSL_CERT_FILE       # Show SSL certificate"
        echo "  env | grep -i cert        # Show all certificate variables"
        echo ""
    fi
}

# Wrapper function for future check_ssl.sh diagnostic (placeholder)
ssl_check() {
    local check_ssl_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_ssl.sh"
    if [ -f "$check_ssl_script" ]; then
        bash "$check_ssl_script" "$@"
    else
        if type ux_info >/dev/null 2>&1; then
            ux_info "check-ssl script coming soon. Running ssl-help for now..."
        fi
        ssl_help "$@"
    fi
}

alias ssl-help='ssl_help'
alias check-ssl='ssl_check'
