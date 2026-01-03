#!/bin/bash
# mytool/setup-crt.sh
# CA Certificate Setup Script
# Installs and manages CA certificates for Node.js/npm
#
# This script reads CA_CERT from shell-common/env/security.local.sh
# Supports both custom certificates and system CA bundle

set -e

# Initialize common tools environment

source "$(dirname "$0")/init.sh" || exit 1

# ========================================
# Load CA_CERT from security.local.sh (Single Source of Truth)
# ========================================
SECURITY_LOCAL="$HOME/dotfiles/shell-common/env/security.local.sh"
SECURITY_EXAMPLE="$HOME/dotfiles/shell-common/env/security.local.example"

# Try to load CA_CERT from security.local.sh
if [ -f "$SECURITY_LOCAL" ]; then
    # shellcheck disable=SC1090
    source "$SECURITY_LOCAL"
elif [ -f "$SECURITY_EXAMPLE" ]; then
    # Fallback to example file (extract default CA_CERT)
    # shellcheck disable=SC1090
    CA_CERT=$(grep -m1 '^CA_CERT=' "$SECURITY_EXAMPLE" | cut -d'"' -f2)
fi

# Validate CA_CERT is set
if [ -z "$CA_CERT" ]; then
    ux_error "CA_CERT not found. Please set it in security.local.sh"
    exit 1
fi

# Extract certificate name from path
CA_CERT_NAME="$(basename "$CA_CERT")"

# Determine CA type
SYSTEM_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
if [ "$CA_CERT" = "$SYSTEM_CA_BUNDLE" ]; then
    IS_SYSTEM_CA=true
else
    IS_SYSTEM_CA=false
fi

# Helper function: Check if certificate is already installed
check_certificate_status() {
    if [ -f "$CA_CERT" ]; then
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
    ux_header "CA Certificate Setup"
    ux_info "Current CA: $CA_CERT"
    echo ""

    # ========================================
    # Handle System CA Bundle (Option 2)
    # ========================================
    if [ "$IS_SYSTEM_CA" = true ]; then
        ux_info "System CA bundle detected. Verifying..."
        echo ""

        if [ -f "$CA_CERT" ]; then
            ux_success "✓ System CA bundle exists: $CA_CERT"

            if verify_env_variable; then
                ux_success "✓ NODE_EXTRA_CA_CERTS is properly set"
            else
                ux_warning "NODE_EXTRA_CA_CERTS is not set"
                ux_info "Run: source ~/.bashrc"
            fi

            echo ""
            ux_info "System CA bundle is ready. No installation needed."
            exit 0
        else
            ux_error "System CA bundle not found at: $CA_CERT"
            ux_info "The system CA bundle should exist by default."
            ux_info "Check your system configuration."
            exit 1
        fi
    fi

    # ========================================
    # Step 1: Check current status (Custom Certificate)
    # ========================================
    ux_step "1/4" "Checking current certificate status..."

    if check_certificate_status; then
        ux_success "Certificate is installed at $CA_CERT"
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
        ux_bullet "1. Obtain the certificate file ($CA_CERT_NAME)"
        ux_bullet "2. Copy it to: $CA_CERT"
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
    if [ -f "$CA_CERT" ]; then
        BACKUP_FILE="${CA_CERT}.backup.$(date +%Y%m%d_%H%M%S)"
        ux_info "Backing up existing certificate to: $BACKUP_FILE"
        if ! sudo cp "$CA_CERT" "$BACKUP_FILE"; then
            ux_error "Failed to backup existing certificate."
            exit 1
        fi
    fi

    # Copy certificate to system directory
    ux_info "Copying certificate to $CA_CERT..."
    if ! sudo cp "$CERT_SOURCE" "$CA_CERT"; then
        ux_error "Failed to copy certificate."
        exit 1
    fi

    # Set appropriate permissions
    if ! sudo chmod 644 "$CA_CERT"; then
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
    if [ -f "$CA_CERT" ]; then
        ux_success "✓ Certificate file exists: $CA_CERT"
    else
        ux_error "✗ Certificate file not found."
        exit 1
    fi

    # Check certificate details
    ux_info "Certificate details:"
    if openssl x509 -in "$CA_CERT" -text -noout 2>/dev/null | grep -q "Subject:"; then
        ux_bullet "$(openssl x509 -in "$CA_CERT" -noout -subject | sed 's/subject=//')"
        ux_bullet "$(openssl x509 -in "$CA_CERT" -noout -issuer | sed 's/issuer=//')"
        ux_bullet "Valid: $(openssl x509 -in "$CA_CERT" -noout -dates | tr '\n' ', ')"
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
    ux_bullet "If NODE_EXTRA_CA_CERTS is not set, check: shell-common/env/security.local.sh"
    ux_bullet "CA_CERT is read from: $SECURITY_LOCAL"
    ux_bullet "To remove certificate: sudo rm $CA_CERT && sudo update-ca-certificates"
    ux_bullet "To view certificate: openssl x509 -in $CA_CERT -text"
    echo ""
}

main "$@"
