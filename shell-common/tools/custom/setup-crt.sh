#!/bin/bash
# mytool/setup-crt.sh
# Samsung Semiconductor CA Certificate Setup Script
# Installs and manages the company proxy certificate for Node.js/npm

set -e

# Source the UX library

source "$(dirname "$0")/../../bash/ux_lib/ux_lib.bash"

# Constants
COMPANY_CA_CERT="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
COMPANY_CA_NAME="samsungsemi-prx.com.crt"

# Helper function: Check if certificate is already installed
check_certificate_status() {
    if [ -f "$COMPANY_CA_CERT" ]; then
        return 0  # Certificate exists
    else
        return 1  # Certificate does not exist
    fi
}

# Helper function: Verify environment variable is set
verify_env_variable() {
    if [ -n "${NODE_EXTRA_CA_CERTS:-}" ] && [ -f "${NODE_EXTRA_CA_CERTS}" ]; then
        return 0  # Environment variable is set and file exists
    else
        return 1  # Environment variable not properly set
    fi
}

# Main script
main() {
    clear
    ux_header "Samsung Semiconductor CA Certificate Setup"
    ux_info "This script helps you install and manage the company proxy certificate."
    echo ""

    # ========================================
    # Step 1: Check current status
    # ========================================
    ux_step "1/4" "Checking current certificate status..."

    if check_certificate_status; then
        ux_success "Certificate is installed at $COMPANY_CA_CERT"
        echo ""

        if verify_env_variable; then
            ux_success "NODE_EXTRA_CA_CERTS environment variable is properly set."
            echo ""

            if ux_confirm "Do you want to update/renew the certificate?" "n"; then
                echo ""
                ux_step "1/4" "Proceeding with certificate update..."
            else
                ux_info "Setup completed. No changes made."
                exit 0
            fi
        else
            ux_warning "NODE_EXTRA_CA_CERTS environment variable is not set."
            ux_info "Try running 'source ~/.bashrc' to reload your shell configuration."
            echo ""
            if ! ux_confirm "Do you want to continue with setup?" "y"; then
                exit 0
            fi
        fi
    else
        ux_warning "Certificate is not installed."
        echo ""
        if ! ux_confirm "Do you want to install the certificate?" "y"; then
            ux_info "Setup cancelled."
            exit 0
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Obtain certificate file
    # ========================================
    ux_step "2/4" "Obtaining certificate file..."

    CERT_SOURCE=""
    echo ""
    ux_section "Certificate Source Options"
    echo "1) From a local file (copy to system certificate directory)"
    echo "2) Manual setup (you will copy the file manually)"
    echo ""

    read -p "Choose option (1 or 2): " choice
    echo ""

    if [ "$choice" = "1" ]; then
        read -p "Enter the path to your certificate file: " cert_path
        cert_path="${cert_path/#\~/$HOME}"  # Expand ~ to HOME

        if [ ! -f "$cert_path" ]; then
            ux_error "Certificate file not found: $cert_path"
            exit 1
        fi

        CERT_SOURCE="$cert_path"
        ux_success "Certificate file found: $CERT_SOURCE"
    elif [ "$choice" = "2" ]; then
        ux_info "Manual setup selected."
        ux_section "Manual Setup Instructions"
        ux_bullet "1. Obtain the certificate file (samsungsemi-prx.com.crt)"
        ux_bullet "2. Copy it to: $COMPANY_CA_CERT"
        ux_bullet "3. Run: sudo update-ca-certificates"
        ux_bullet "4. Verify: echo \$NODE_EXTRA_CA_CERTS"
        echo ""
        ux_info "After completing manual setup, reload your shell:"
        ux_bullet "source ~/.bashrc"
        exit 0
    else
        ux_error "Invalid choice."
        exit 1
    fi
    echo ""

    # ========================================
    # Step 3: Install certificate
    # ========================================
    ux_step "3/4" "Installing certificate..."
    echo ""

    if ! command -v sudo &>/dev/null; then
        ux_error "sudo is not available. Certificate installation requires root privileges."
        exit 1
    fi

    # Create backup if certificate already exists
    if [ -f "$COMPANY_CA_CERT" ]; then
        BACKUP_FILE="${COMPANY_CA_CERT}.backup.$(date +%Y%m%d_%H%M%S)"
        ux_info "Backing up existing certificate to: $BACKUP_FILE"
        if ! sudo cp "$COMPANY_CA_CERT" "$BACKUP_FILE"; then
            ux_error "Failed to backup existing certificate."
            exit 1
        fi
    fi

    # Copy certificate to system directory
    ux_info "Copying certificate to $COMPANY_CA_CERT..."
    if ! sudo cp "$CERT_SOURCE" "$COMPANY_CA_CERT"; then
        ux_error "Failed to copy certificate."
        exit 1
    fi

    # Set appropriate permissions
    if ! sudo chmod 644 "$COMPANY_CA_CERT"; then
        ux_error "Failed to set certificate permissions."
        exit 1
    fi

    # Update system certificates
    ux_info "Updating system certificate store..."
    if ! ux_with_spinner "Running update-ca-certificates" sudo update-ca-certificates --fresh; then
        ux_error "Failed to update system certificates."
        exit 1
    fi

    ux_success "Certificate installed successfully."
    echo ""

    # ========================================
    # Step 4: Verify installation
    # ========================================
    ux_step "4/4" "Verifying installation..."
    echo ""

    # Check if certificate file exists
    if [ -f "$COMPANY_CA_CERT" ]; then
        ux_success "✓ Certificate file exists: $COMPANY_CA_CERT"
    else
        ux_error "✗ Certificate file not found."
        exit 1
    fi

    # Check certificate details
    ux_info "Certificate details:"
    if openssl x509 -in "$COMPANY_CA_CERT" -text -noout 2>/dev/null | grep -q "Subject:"; then
        ux_bullet "$(openssl x509 -in "$COMPANY_CA_CERT" -noout -subject | sed 's/subject=//')"
        ux_bullet "$(openssl x509 -in "$COMPANY_CA_CERT" -noout -issuer | sed 's/issuer=//')"
        ux_bullet "Valid: $(openssl x509 -in "$COMPANY_CA_CERT" -noout -dates | tr '\n' ', ')"
    else
        ux_warning "Could not parse certificate details."
    fi
    echo ""

    # Check environment variable (may not be set yet in current session)
    ux_info "To activate the NODE_EXTRA_CA_CERTS environment variable:"
    ux_bullet "source ~/.bashrc"
    echo ""

    # ========================================
    # Completion
    # ========================================
    ux_header "✅ Certificate Setup Complete!"
    ux_section "Next Steps"
    ux_bullet "1. Reload your shell: source ~/.bashrc"
    ux_bullet "2. Verify NODE_EXTRA_CA_CERTS: echo \$NODE_EXTRA_CA_CERTS"
    ux_bullet "3. Test npm: npm config get registry"
    echo ""

    ux_section "Troubleshooting"
    ux_bullet "If NODE_EXTRA_CA_CERTS is not set, check: bash/env/security.bash"
    ux_bullet "To remove certificate: sudo rm $COMPANY_CA_CERT && sudo update-ca-certificates"
    ux_bullet "To view certificate: openssl x509 -in $COMPANY_CA_CERT -text"
    echo ""
}

main "$@"
