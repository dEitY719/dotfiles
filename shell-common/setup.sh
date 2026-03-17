#!/bin/sh
# shell-common/setup.sh
# Environment-specific configuration setup for shell-common

set -e

# Get the directory where this script is located (sh-compatible)
SHELL_COMMON_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source UX library for consistent output styling (sh-compatible: use . instead of source)
if [ -f "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh" ]; then
    . "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh"
else
    # Fallback: define basic functions if ux_lib is not available
    ux_header() { echo "=== $1 ==="; }
    ux_section() { echo ""; echo "$1"; }
    ux_success() { echo "✓ $1"; }
    ux_info() { echo "ℹ $1"; }
    ux_error() { echo "✗ $1" >&2; }
fi

# ============================================================================
# Configuration Values (SSOT - Single Source of Truth)
# ============================================================================
# These are extracted settings values for maintainability
# If values change, update only here (not in sed patterns)
# Note: Using sh-compatible variable naming (no associative arrays)

# Security configuration
SECURITY_CONFIG_external="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
SECURITY_CONFIG_internal="/etc/ssl/certs/ca-certificates.crt"

# NPM Registry configuration
NPM_REGISTRY_external="https://registry.npmjs.org/"
NPM_REGISTRY_internal="http://repo.samsungds.net:8081/artifactory/api/npm/npm/"

# NPM CA File configuration
NPM_CAFILE_external="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
NPM_CAFILE_internal="/etc/ssl/certs/ca-certificates.crt"

# NPM Strict SSL configuration
NPM_STRICT_SSL_external="true"
NPM_STRICT_SSL_internal="false"

# NPM Proxy configuration
NPM_PROXY_external=""
NPM_PROXY_internal="http://12.26.204.100:8080"

# NPM No-proxy configuration
NPM_NOPROXY_external=""
NPM_NOPROXY_internal="10.229.95.200,10.229.95.220,12.36.155.91,12.36.154.116,12.36.154.130,localhost,127.0.0.1,.samsung.net,.samsungds.net,dsvdi.net,pfs.nprotect.com"

# HTTP Proxy configuration
PROXY_HTTP_internal="http://12.26.204.100:8080/"

# No-proxy configuration
PROXY_NO_internal="10.229.95.200,10.229.95.220,12.36.155.91,12.36.154.116,12.36.154.130,localhost,127.0.0.1,.samsung.net,.samsungds.net,ssai.samsungds.net,dsvdi.net,pfs.nprotect.com"

# ============================================================================
# Helper Functions
# ============================================================================

cleanup_local_files() {
    # Find all .local.sh files
    ux_header "Cleaning up environment-specific files"

    # Delete all .local.sh files (sh-compatible approach)
    if find "$SHELL_COMMON_DIR" -name "*.local.sh" -type f >/dev/null 2>&1; then
        find "$SHELL_COMMON_DIR" -name "*.local.sh" -type f | while IFS= read -r local_file; do
            rm -f "$local_file"
            ux_success "Removed: ${local_file#"$SHELL_COMMON_DIR"/}"
        done
    else
        ux_info "No .local.sh files found"
        return 0
    fi
}

copy_local_files() {
    environment="$1"

    ux_header "Copying template files for: $environment"

    # Copy .local.example files to .local.sh (sh-compatible approach)
    find "$SHELL_COMMON_DIR" -name "*.local.example" -type f | while IFS= read -r example_file; do
        dir="$(dirname "$example_file")"
        filename="$(basename "$example_file" .example)"
        local_file="${dir}/${filename%.*}.local.sh"
        basename_file="$(basename "$example_file")"

        # Environment-specific handling
        case "$environment" in
            internal)
                # Internal company PC: copy ALL .local.example files
                cp "$example_file" "$local_file"
                ux_success "Created: ${local_file#"$SHELL_COMMON_DIR"/}"
                ;;
            external)
                # External company PC (VPN): skip proxy.local.example
                # Reason: proxy.local.sh is only valid for internal environment
                if [ "$basename_file" = "proxy.local.example" ]; then
                    ux_info "Skipped (not needed for VPN): ${basename_file}"
                else
                    cp "$example_file" "$local_file"
                    ux_success "Created: ${local_file#"$SHELL_COMMON_DIR"/}"
                fi
                ;;
        esac
    done
}

read_config_value() {
    environment="$1"
    config_key="$2"
    config_file="${SHELL_COMMON_DIR}/config/environments.conf"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    grep "^${environment}:${config_key}=" "$config_file" 2>/dev/null | cut -d= -f2- | sed 's/"//g'
}

setup_security_config() {
    environment="$1"
    security_template="${SHELL_COMMON_DIR}/env/security.local.example"
    security_local="${SHELL_COMMON_DIR}/env/security.local.sh"

    # Try to get CA_CERT from environments.conf (Stage 3 approach)
    ca_cert="$(read_config_value "$environment" "CA_CERT")"

    # Fallback to predefined variables (Stage 1-2 approach)
    if [ -z "$ca_cert" ]; then
        eval "ca_cert=\$SECURITY_CONFIG_${environment}"
    fi

    if [ -z "$ca_cert" ]; then
        ux_error "Unknown environment: $environment"
        return 1
    fi

    case "$environment" in
        internal)
            ux_info "Configuring security for internal company PC (System CA)"
            # Comment out Option 1, Uncomment Option 2
            if [ -f "$security_local" ]; then
                sed -i 's/^CA_CERT="\/usr\/local\/share/#CA_CERT="\/usr\/local\/share/' "$security_local"
                sed -i 's/^#CA_CERT="\/etc\/ssl\/certs/CA_CERT="\/etc\/ssl\/certs/' "$security_local"
                # SSL_CERT_FILE: Option 2 (McAfee) is already active - verify it
                # (no sed needed: McAfee cert is default in security.local.example)
            fi
            ux_success "CA Certificate: ${ca_cert}"
            ux_success "SSL Certificate: /usr/share/ca-certificates/extra/McAfee_Certificate.crt"
            ;;
        external)
            ux_info "Configuring security for external company PC (Custom Certificate)"
            if [ -f "$security_local" ]; then
                sed -i 's/^#CA_CERT="\/usr\/local\/share/CA_CERT="\/usr\/local\/share/' "$security_local"
                sed -i 's/^CA_CERT="\/etc\/ssl\/certs/#CA_CERT="\/etc\/ssl\/certs/' "$security_local"
                # SSL_CERT_FILE: Comment out McAfee (Option 2), Uncomment samsungsemi (Option 1)
                sed -i 's/^SSL_CERT_FILE="\/usr\/share\/ca-certificates/#SSL_CERT_FILE="\/usr\/share\/ca-certificates/' "$security_local"
                sed -i 's/^#SSL_CERT_FILE="\/usr\/local\/share/SSL_CERT_FILE="\/usr\/local\/share/' "$security_local"
            fi
            ux_success "CA Certificate: ${ca_cert}"
            ux_success "SSL Certificate: /usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
            ;;
    esac
}

setup_npm_config() {
    environment="$1"
    npm_local="${SHELL_COMMON_DIR}/tools/integrations/npm.local.sh"

    if [ ! -f "$npm_local" ]; then
        return 0
    fi

    # Get configuration values
    registry="$(read_config_value "$environment" "NPM_REGISTRY")"
    if [ -z "$registry" ]; then
        eval "registry=\$NPM_REGISTRY_${environment}"
    fi

    proxy="$(read_config_value "$environment" "NPM_PROXY")"
    if [ -z "$proxy" ]; then
        eval "proxy=\$NPM_PROXY_${environment}"
    fi

    if [ -z "$registry" ]; then
        ux_error "Unknown environment: $environment"
        return 1
    fi

    case "$environment" in
        internal)
            ux_info "Configuring NPM for internal company PC (Artifactory + Proxy)"
            # Comment out Option 1 lines
            sed -i '/^    # === Option1:/,/^    # === Option2:/ {
                /DESIRED_REGISTRY=.*npmjs/s/^    /    # /
                /DESIRED_CAFILE=.*samsungsemi/s/^    /    # /
                /DESIRED_STRICT_SSL="true"/s/^    /    # /
                /DESIRED_PROXY=""/s/^    /    # /
                /DESIRED_HTTPS_PROXY=""/s/^    /    # /
                /DESIRED_NOPROXY=""/s/^    /    # /
            }' "$npm_local"
            # Uncomment Option 2 lines
            sed -i '/^    # === Option2:/,/^    # === 공통 설정/ {
                /DESIRED_REGISTRY=.*artifactory/s/^    # /    /
                /DESIRED_CAFILE=.*ca-certificates.crt/s/^    # /    /
                /DESIRED_STRICT_SSL="false"/s/^    # /    /
                /DESIRED_PROXY=.*12.26/s/^    # /    /
                /DESIRED_HTTPS_PROXY=.*12.26/s/^    # /    /
                /DESIRED_NOPROXY=.*10.229/s/^    # /    /
            }' "$npm_local"
            ux_success "NPM Registry: $registry"
            ux_success "NPM Proxy: $proxy"
            ;;
        external)
            ux_info "Configuring NPM for external company PC (npmjs + No Proxy)"
            # Uncomment Option 1 lines
            sed -i '/^    # === Option1:/,/^    # === Option2:/ {
                /DESIRED_REGISTRY=.*npmjs/s/^    # /    /
                /DESIRED_CAFILE=.*samsungsemi/s/^    # /    /
                /DESIRED_STRICT_SSL="true"/s/^    # /    /
                /DESIRED_PROXY=""/s/^    # /    /
                /DESIRED_HTTPS_PROXY=""/s/^    # /    /
                /DESIRED_NOPROXY=""/s/^    # /    /
            }' "$npm_local"
            # Comment out Option 2 lines
            sed -i '/^    # === Option2:/,/^    # === 공통 설정/ {
                /DESIRED_REGISTRY=.*artifactory/s/^    /    # /
                /DESIRED_CAFILE=.*ca-certificates.crt/s/^    /    # /
                /DESIRED_STRICT_SSL="false"/s/^    /    # /
                /DESIRED_PROXY=.*12.26/s/^    /    # /
                /DESIRED_HTTPS_PROXY=.*12.26/s/^    /    # /
                /DESIRED_NOPROXY=.*10.229/s/^    /    # /
            }' "$npm_local"
            ux_success "NPM Registry: $registry"
            ux_success "NPM Proxy: (none - direct connection)"
            ;;
    esac
}

verify_config() {
    environment="$1"

    ux_header "Verifying configuration for: $environment"

    # Verify npm config if npm is available
    if command -v npm >/dev/null 2>&1; then
        npm_registry="$(npm config get registry 2>/dev/null || echo "unknown")"
        ux_info "npm registry: $npm_registry"

        npm_cafile="$(npm config get cafile 2>/dev/null || echo "none")"
        ux_info "npm cafile: $npm_cafile"
    else
        ux_info "npm is not installed, skipping npm config verification"
    fi

    # Verify CA cert is accessible if configured
    if [ -n "$SHELL_COMMON_DIR" ]; then
        ca_cert=""
        eval "ca_cert=\$SECURITY_CONFIG_${environment}"
        if [ -n "$ca_cert" ] && [ -f "$ca_cert" ]; then
            ux_success "CA Certificate accessible: $ca_cert"
        elif [ -n "$ca_cert" ]; then
            ux_info "CA Certificate not found yet: $ca_cert (will be installed by setup_crt.sh)"
        fi
    fi
}

setup_local_files() {
    environment="$1"

    ux_header "Setting up environment-specific files for: $environment"

    # Stage 1: Copy template files
    copy_local_files "$environment"

    # Stage 2: Configure each setting type
    setup_security_config "$environment"
    setup_npm_config "$environment"

    # Stage 3: Verify configuration
    verify_config "$environment"
}

setup_uv_config() {
    environment="$1"
    uv_config_dir="${HOME}/.config/uv"
    uv_conf="${uv_config_dir}/uv.toml"

    # Ensure ~/.config/uv directory exists
    mkdir -p "$uv_config_dir"

    ux_header "Setting up uv configuration for: $environment"

    # Remove existing uv.toml (symlink or file)
    if [ -e "$uv_conf" ] || [ -L "$uv_conf" ]; then
        rm -f "$uv_conf"
        ux_info "Removed existing: $uv_conf"
    fi

    # Create symlink based on environment
    case "$environment" in
        internal)
            # Internal company PC: use internal repository + proxy
            ln -s "${SHELL_COMMON_DIR}/config/uv/uv.toml.internal" "$uv_conf"
            ux_success "Created symlink: $uv_conf → uv.toml.internal"
            ux_info "Using: Samsung internal repositories + proxy"
            ;;
        external|public)
            # External/Public: no uv.toml needed (defaults to public PyPI)
            ux_info "No uv.toml needed (using default public PyPI)"
            ;;
    esac
}

setup_pip_config() {
    environment="$1"
    pip_config_dir="${HOME}/.config/pip"
    pip_conf="${pip_config_dir}/pip.conf"

    # Ensure ~/.config/pip directory exists
    mkdir -p "$pip_config_dir"

    ux_header "Setting up pip configuration for: $environment"

    # Remove existing pip.conf if it exists
    if [ -f "$pip_conf" ]; then
        rm -f "$pip_conf"
        ux_info "Removed existing: $pip_conf"
    fi

    # Create symlink based on environment
    case "$environment" in
        internal)
            # Internal company PC: use internal repository
            ln -s "${SHELL_COMMON_DIR}/config/pip/pip.conf.internal" "$pip_conf"
            ux_success "Created symlink: $pip_conf → pip.conf.internal"
            ux_info "Using: Samsung internal repositories"
            ;;
        external)
            # External company PC (VPN): use public PyPI
            ln -s "${SHELL_COMMON_DIR}/config/pip/pip.conf.external" "$pip_conf"
            ux_success "Created symlink: $pip_conf → pip.conf.external"
            ux_info "Using: Public PyPI"
            ;;
        public)
            # Public PC (home): use public PyPI
            ln -s "${SHELL_COMMON_DIR}/config/pip/pip.conf.external" "$pip_conf"
            ux_success "Created symlink: $pip_conf → pip.conf.external"
            ux_info "Using: Public PyPI"
            ;;
    esac
}

# ============================================================================
# Main Menu
# ============================================================================

main() {
    echo ""
    ux_header "Shell-Common Environment Setup"
    echo ""
    echo "Select your environment:"
    echo ""
    echo "1) Public PC (home environment)"
    echo "2) Internal company PC (direct connection)"
    echo "3) External company PC (VPN)"
    echo ""

    printf "Enter your choice (1-3): "
    read -r choice
    echo ""

    case "$choice" in
        1)
            ux_info "Selected: Public PC"
            cleanup_local_files
            setup_pip_config "public"
            setup_uv_config "public"
            echo "$choice" > "$HOME/.dotfiles-setup-mode"
            echo ""
            ux_success "Setup complete for public PC (home environment)"
            ux_info "All environment-specific configuration removed"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ;;
        2)
            ux_info "Selected: Internal company PC (direct connection)"
            cleanup_local_files
            setup_local_files "internal"
            setup_pip_config "internal"
            setup_uv_config "internal"
            echo "$choice" > "$HOME/.dotfiles-setup-mode"
            echo ""
            ux_success "Setup complete for internal company PC"
            ux_info "Changes made:"
            ux_info "  - Copied all .local.example files to .local.sh"
            ux_info "  - Security: System CA Bundle (Option 2) activated"
            ux_info "  - SSL Certificate: McAfee (/usr/share/ca-certificates/extra/McAfee_Certificate.crt)"
            ux_info "  - Proxy: Company proxy (12.26.204.100:8080) configured"
            ux_info "  - Pip: Samsung internal repository configured"
            ux_info "  - uv: Samsung internal repository + proxy configured"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ux_section "⚠️  IMPORTANT: Reload your shell to apply changes"
            ux_bullet "Option 1 (Current shell): source ~/.bashrc"
            ux_bullet "Option 2 (New shell): exec bash  or  exec zsh"
            ux_bullet "Verify: ssl-help  (or: echo \$SSL_CERT_FILE)"
            echo ""
            ;;
        3)
            ux_info "Selected: External company PC (VPN)"
            cleanup_local_files
            setup_local_files "external"
            setup_pip_config "external"
            setup_uv_config "external"
            echo "$choice" > "$HOME/.dotfiles-setup-mode"
            echo ""
            ux_success "Setup complete for external company PC"
            ux_info "Changes made:"
            ux_info "  - Copied .local.example files to .local.sh (except proxy)"
            ux_info "  - Security: Custom Certificate (Option 1) activated"
            ux_info "  - SSL Certificate: samsungsemi (/usr/local/share/ca-certificates/samsungsemi-prx.com.crt)"
            ux_info "  - Proxy: Skipped (not needed for VPN - direct connection)"
            ux_info "  - Pip: Public PyPI configured"
            ux_info "  - Next: Run 'setup_crt.sh' to install the certificate"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ux_section "⚠️  IMPORTANT: Reload your shell to apply changes"
            ux_bullet "Option 1 (Current shell): source ~/.bashrc"
            ux_bullet "Option 2 (New shell): exec bash  or  exec zsh"
            ux_bullet "Verify: ssl-help  (or: echo \$SSL_CERT_FILE)"
            echo ""
            ;;
        *)
            ux_error "Invalid choice. Please run again and select 1, 2, or 3."
            exit 1
            ;;
    esac
}

main "$@"
