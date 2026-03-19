#!/bin/sh
# shell-common/setup.sh
# Environment-specific configuration setup for shell-common

set -e

# Get the directory where this script is located (sh-compatible)
SHELL_COMMON_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SHELL_COMMON_DIR/.." && pwd)"

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

# Tool-specific configurations are managed via tracked files at project root
# and symlinked to their respective locations:
#   npm/   → ~/.npmrc
#   pip/   → ~/.config/pip/pip.conf
#   uv/    → ~/.config/uv/uv.toml

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

setup_security_config() {
    environment="$1"
    security_template="${SHELL_COMMON_DIR}/env/security.local.example"
    security_local="${SHELL_COMMON_DIR}/env/security.local.sh"

    # Get CA_CERT path from predefined variables
    case "$environment" in
        internal) ca_cert="$SECURITY_CONFIG_internal" ;;
        external) ca_cert="$SECURITY_CONFIG_external" ;;
        *) ca_cert="" ;;
    esac

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

setup_npm_symlink() {
    environment="$1"
    npmrc_target="$HOME/.npmrc"

    ux_header "Setting up npm configuration for: $environment"

    # Handle existing ~/.npmrc (symlink, file, or directory)
    if [ -L "$npmrc_target" ]; then
        rm -f "$npmrc_target"
        ux_info "Removed existing symlink: $npmrc_target"
    elif [ -d "$npmrc_target" ]; then
        backup="${npmrc_target}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$npmrc_target" "$backup"
        ux_warning "Backed up existing directory: $backup"
    elif [ -f "$npmrc_target" ]; then
        backup="${npmrc_target}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$npmrc_target" "$backup"
        ux_info "Backed up existing file: $backup"
    fi

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "${DOTFILES_ROOT}/npm/npmrc.internal" "$npmrc_target"
            ux_success "Created symlink: ~/.npmrc → npm/npmrc.internal"
            ux_info "Using: Samsung internal Nexus repository + proxy"
            ;;
        external)
            ln -s "${DOTFILES_ROOT}/npm/npmrc.external" "$npmrc_target"
            ux_success "Created symlink: ~/.npmrc → npm/npmrc.external"
            ux_info "Using: Public npmjs registry (no proxy)"
            ;;
        public)
            # Public PC: no .npmrc needed (defaults)
            ux_info "No .npmrc needed (using npm defaults)"
            ;;
    esac
}

verify_config() {
    environment="$1"

    ux_header "Verifying configuration for: $environment"

    # Verify CA cert is accessible if configured
    case "$environment" in
        internal) ca_cert="$SECURITY_CONFIG_internal" ;;
        external) ca_cert="$SECURITY_CONFIG_external" ;;
        *) ca_cert="" ;;
    esac
    if [ -n "$ca_cert" ] && [ -f "$ca_cert" ]; then
        ux_success "CA Certificate accessible: $ca_cert"
    elif [ -n "$ca_cert" ]; then
        ux_info "CA Certificate not found yet: $ca_cert (will be installed by setup_crt.sh)"
    fi
}

setup_local_files() {
    environment="$1"

    ux_header "Setting up environment-specific files for: $environment"

    # Stage 1: Copy template files
    copy_local_files "$environment"

    # Stage 2: Configure each setting type
    setup_security_config "$environment"

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

    # Handle existing uv.toml (symlink, file, or directory)
    if [ -L "$uv_conf" ]; then
        rm -f "$uv_conf"
        ux_info "Removed existing symlink: $uv_conf"
    elif [ -d "$uv_conf" ]; then
        backup="${uv_conf}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$uv_conf" "$backup"
        ux_warning "Backed up existing directory: $backup"
    elif [ -f "$uv_conf" ]; then
        backup="${uv_conf}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$uv_conf" "$backup"
        ux_info "Backed up existing file: $backup"
    fi

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "${DOTFILES_ROOT}/uv/uv.toml.internal" "$uv_conf"
            ux_success "Created symlink: ~/.config/uv/uv.toml → uv/uv.toml.internal"
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

    # Handle existing pip.conf (symlink, file, or directory)
    if [ -L "$pip_conf" ]; then
        rm -f "$pip_conf"
        ux_info "Removed existing symlink: $pip_conf"
    elif [ -d "$pip_conf" ]; then
        backup="${pip_conf}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$pip_conf" "$backup"
        ux_warning "Backed up existing directory: $backup"
    elif [ -f "$pip_conf" ]; then
        backup="${pip_conf}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$pip_conf" "$backup"
        ux_info "Backed up existing file: $backup"
    fi

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "${DOTFILES_ROOT}/pip/pip.conf.internal" "$pip_conf"
            ux_success "Created symlink: ~/.config/pip/pip.conf → pip/pip.conf.internal"
            ux_info "Using: Samsung internal repositories"
            ;;
        external|public)
            ln -s "${DOTFILES_ROOT}/pip/pip.conf.external" "$pip_conf"
            ux_success "Created symlink: ~/.config/pip/pip.conf → pip/pip.conf.external"
            ux_info "Using: Public PyPI"
            ;;
    esac
}

setup_rpm_repo() {
    environment="$1"
    repo_target="/etc/yum.repos.d/ds.repo"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up RPM repository configuration for: $environment"

    # Gate 1: Only proceed if yum or dnf is available
    if ! command -v yum >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1; then
        ux_info "Skipped: yum/dnf not found (not a RHEL/CentOS system)"
        return 0
    fi

    # Gate 2: Verify RHEL 8 — do not deploy RHEL 8.6 repos to Fedora/Rocky/RHEL 9
    if [ -f /etc/os-release ]; then
        _rpm_os_id="$(. /etc/os-release && echo "${ID:-}")"
        _rpm_os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
        case "$_rpm_os_id" in
            rhel|centos)
                case "$_rpm_os_version" in
                    8|8.*) ;; # RHEL 8.x — proceed
                    *)
                        ux_info "Skipped: RHEL ${_rpm_os_version} detected (repo is RHEL 8.6 only)"
                        return 0
                        ;;
                esac
                ;;
            *)
                ux_info "Skipped: ${_rpm_os_id} detected (repo is RHEL 8 only)"
                return 0
                ;;
        esac
    fi

    # Gate 3: Verify privilege — use sudo if needed, skip if unavailable
    _rpm_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _rpm_run_privileged=""  # already root, no sudo needed
    elif command -v sudo >/dev/null 2>&1; then
        _rpm_run_privileged="sudo"
        ux_info "Root privileges required for /etc/yum.repos.d/ — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    case "$environment" in
        internal)
            # Ensure target directory exists
            if [ ! -d "/etc/yum.repos.d" ]; then
                $_rpm_run_privileged mkdir -p "/etc/yum.repos.d"
                ux_info "Created directory: /etc/yum.repos.d"
            fi

            # Backup existing repo file if present
            if [ -f "$repo_target" ]; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up existing file: $backup"
            fi

            # Copy (not symlink) since this is a system-level config in /etc/
            $_rpm_run_privileged cp "${DOTFILES_ROOT}/rpm/ds.repo.internal" "$repo_target"
            ux_success "Copied: rpm/ds.repo.internal → $repo_target"
            ux_info "Using: Samsung DS internal repositories (RHEL 8.6)"
            ;;
        external|public)
            # Only remove if the file was deployed by dotfiles (has marker)
            if [ -f "$repo_target" ] && grep -q "$marker" "$repo_target" 2>/dev/null; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up and removed dotfiles-managed repo: $backup"
            elif [ -f "$repo_target" ]; then
                ux_info "Existing $repo_target is not managed by dotfiles — leaving untouched"
            fi
            ;;
    esac
}

setup_apt_sources() {
    environment="$1"
    sources_target="/etc/apt/sources.list"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up APT sources configuration for: $environment"

    # Gate 1: Only proceed if apt is available
    if ! command -v apt >/dev/null 2>&1; then
        ux_info "Skipped: apt not found (not a Debian/Ubuntu system)"
        return 0
    fi

    # Gate 2: Verify Ubuntu codename — match against available config files
    _apt_codename=""
    if [ -f /etc/os-release ]; then
        _apt_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    fi
    _apt_source="${DOTFILES_ROOT}/apt/sources.list.${_apt_codename}.internal"
    if [ -z "$_apt_codename" ] || [ ! -f "$_apt_source" ]; then
        ux_info "Skipped: no apt config for '${_apt_codename:-unknown}' (available: $(ls "${DOTFILES_ROOT}"/apt/sources.list.*.internal 2>/dev/null | sed 's/.*sources\.list\.\(.*\)\.internal/\1/' | tr '\n' ' ' || echo 'none'))"
        return 0
    fi

    # Gate 3: Verify privilege — use sudo if needed, skip if unavailable
    _apt_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _apt_run_privileged=""
    elif command -v sudo >/dev/null 2>&1; then
        _apt_run_privileged="sudo"
        ux_info "Root privileges required for /etc/apt/sources.list — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    case "$environment" in
        internal)
            # Backup existing sources.list if present and not already managed
            if [ -f "$sources_target" ]; then
                if ! grep -q "$marker" "$sources_target" 2>/dev/null; then
                    backup="${sources_target}.backup.$(date +%Y%m%d%H%M%S)"
                    $_apt_run_privileged cp "$sources_target" "$backup"
                    ux_info "Backed up original: $backup"
                fi
            fi

            $_apt_run_privileged cp "$_apt_source" "$sources_target"
            ux_success "Copied: apt/sources.list.${_apt_codename}.internal → $sources_target"
            ux_info "Using: Samsung internal Nexus mirror (Ubuntu ${_apt_codename})"
            ux_info "Run 'sudo apt update' to refresh package lists"
            ;;
        external|public)
            # Only restore if current file was deployed by dotfiles
            if [ -f "$sources_target" ] && grep -q "$marker" "$sources_target" 2>/dev/null; then
                # Find the most recent non-dotfiles backup
                _apt_latest_backup="$(ls -t "${sources_target}".backup.* 2>/dev/null | head -1)"
                if [ -n "$_apt_latest_backup" ]; then
                    $_apt_run_privileged cp "$_apt_latest_backup" "$sources_target"
                    ux_success "Restored original: $_apt_latest_backup → $sources_target"
                else
                    $_apt_run_privileged rm -f "$sources_target"
                    ux_warning "Removed dotfiles-managed sources.list (no backup found to restore)"
                fi
            elif [ -f "$sources_target" ]; then
                ux_info "Existing $sources_target is not managed by dotfiles — leaving untouched"
            fi
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
            setup_npm_symlink "public"
            setup_pip_config "public"
            setup_uv_config "public"
            setup_rpm_repo "public"
            setup_apt_sources "public"
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
            setup_npm_symlink "internal"
            setup_pip_config "internal"
            setup_uv_config "internal"
            setup_rpm_repo "internal"
            setup_apt_sources "internal"
            echo "$choice" > "$HOME/.dotfiles-setup-mode"
            echo ""
            ux_success "Setup complete for internal company PC"
            ux_info "Changes made:"
            ux_info "  - Copied all .local.example files to .local.sh"
            ux_info "  - Security: System CA Bundle (Option 2) activated"
            ux_info "  - SSL Certificate: McAfee (/usr/share/ca-certificates/extra/McAfee_Certificate.crt)"
            ux_info "  - Proxy: Company proxy (12.26.204.100:8080) configured"
            ux_info "  - NPM: ~/.npmrc → npm/npmrc.internal (Nexus + proxy)"
            ux_info "  - Pip: Samsung internal repository configured"
            ux_info "  - uv: Samsung internal repository + proxy configured"
            ux_info "  - RPM: /etc/yum.repos.d/ds.repo (if yum/dnf available)"
            ux_info "  - APT: /etc/apt/sources.list (if Ubuntu jammy)"
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
            setup_npm_symlink "external"
            setup_pip_config "external"
            setup_uv_config "external"
            setup_rpm_repo "external"
            setup_apt_sources "external"
            echo "$choice" > "$HOME/.dotfiles-setup-mode"
            echo ""
            ux_success "Setup complete for external company PC"
            ux_info "Changes made:"
            ux_info "  - Copied .local.example files to .local.sh (except proxy)"
            ux_info "  - Security: Custom Certificate (Option 1) activated"
            ux_info "  - SSL Certificate: samsungsemi (/usr/local/share/ca-certificates/samsungsemi-prx.com.crt)"
            ux_info "  - Proxy: Skipped (not needed for VPN - direct connection)"
            ux_info "  - NPM: ~/.npmrc → npm/npmrc.external (npmjs + no proxy)"
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
