#!/bin/sh
# shell-common/functions/ssl_help.sh
# SSL certificate help function (bash/zsh compatible)
#
# Purpose: Provide SSL certificate configuration diagnostics
# Usage: ssl-help [all|env|file|path]

ssl_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "SSL Certificate Configuration & Diagnostics"
    else
        echo "=== SSL Certificate Configuration & Diagnostics ==="
    fi

    if type ux_section >/dev/null 2>&1; then
        # === Quick Status Check ===
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
        echo ""

        if [ -n "$REQUESTS_CA_BUNDLE" ]; then
            ux_success "REQUESTS_CA_BUNDLE: $REQUESTS_CA_BUNDLE (Python requests)"
        else
            ux_info "REQUESTS_CA_BUNDLE: [NOT SET]"
        fi
        echo ""

        if [ -n "$NODE_EXTRA_CA_CERTS" ]; then
            ux_success "NODE_EXTRA_CA_CERTS: $NODE_EXTRA_CA_CERTS (Node.js)"
        else
            ux_info "NODE_EXTRA_CA_CERTS: [NOT SET]"
        fi
        echo ""

        # === Quick Commands ===
        ux_section "Quick Commands"
        ux_bullet "echo \$SSL_CERT_FILE                  Show SSL certificate file"
        ux_bullet "echo \$REQUESTS_CA_BUNDLE             Show Python requests CA bundle"
        ux_bullet "env | grep -i cert                   Show all certificate vars"
        echo ""

        # === File Status ===
        ux_section "Security Configuration Files"
        local security_local="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/env/security.local.sh"
        if [ -f "$security_local" ]; then
            ux_success "security.local.sh: exists"
            ux_bullet "Location: $security_local"
        else
            ux_info "security.local.sh: not configured (public environment)"
        fi
        echo ""

        # === For Corporate Environments ===
        ux_section "Corporate Environment Setup"
        ux_info "1. Run setup.sh to configure SSL certificates"
        ux_bullet "  cd ~/dotfiles"
        ux_bullet "  ./setup.sh"
        ux_bullet "  Select: [2] Internal company PC OR [3] External company PC"
        echo ""

        ux_section "Certificate Paths by Environment"
        ux_bullet "Internal PC:  /usr/share/ca-certificates/extra/McAfee_Certificate.crt"
        ux_bullet "External PC:  /usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
        ux_bullet "System CA:    /etc/ssl/certs/ca-certificates.crt"
        echo ""

        # === Tools & Libraries ===
        ux_section "Tools That Use SSL_CERT_FILE"
        ux_bullet "curl                 - Web requests and downloads"
        ux_bullet "wget                 - File downloads"
        ux_bullet "git                  - Git operations (HTTPS)"
        ux_bullet "python (requests)    - HTTP library"
        ux_bullet "npm                  - Node.js package manager"
        echo ""

        # === Verification ===
        ux_section "Verify Certificate Installation"
        ux_info "Check if certificate file exists:"
        if [ -n "$SSL_CERT_FILE" ] && [ -f "$SSL_CERT_FILE" ]; then
            ux_success "✓ Certificate file is accessible"
            ux_bullet "openssl x509 -in \$SSL_CERT_FILE -text -noout   View cert details"
        else
            ux_warning "Certificate file not found - may need setup or installation"
        fi
        echo ""

        # === Important Notes ===
        ux_section "Important Notes"
        ux_warning "Different variables for different tools:"
        ux_info "  - SSL_CERT_FILE:        curl, wget, git"
        ux_info "  - REQUESTS_CA_BUNDLE:   Python requests"
        ux_info "  - NODE_EXTRA_CA_CERTS:  Node.js"
        echo ""

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
        # For now, just show ssl-help since check_ssl.sh doesn't exist yet
        if type ux_info >/dev/null 2>&1; then
            ux_info "check-ssl script coming soon. Running ssl-help for now..."
        fi
        ssl_help "$@"
    fi
}

# Aliases for ssl-help and check-ssl
alias ssl-help='ssl_help'
alias check-ssl='ssl_check'
