#!/bin/bash
# shell-common/tools/custom/check_npm.sh
# Comprehensive npm configuration diagnostic script
# Usage: check_npm [config|files|env|registry|packages|all]

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
source "$(dirname "$0")/init.sh" || exit 1

# ============================================================
# Helper functions
# ============================================================

_format_setting() {
    local label="$1"
    local value="${2:-[NOT SET]}"
    printf "  %-35s : %s\n" "$label" "$value"
}

_npm_config_get() {
    local value
    value="$(npm config get "$1" 2>/dev/null)"
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "[NOT SET]"
    else
        echo "$value"
    fi
}

# ============================================================
# Diagnostic functions
# ============================================================

check_npm_config() {
    ux_header "1. NPM Configuration"

    ux_section "Registry & Security"
    _format_setting "Registry" "$(_npm_config_get registry)"
    _format_setting "CA File" "$(_npm_config_get cafile)"
    _format_setting "Strict SSL" "$(_npm_config_get strict-ssl)"
    echo ""

    ux_section "Proxy Settings"
    _format_setting "Proxy" "$(_npm_config_get proxy)"
    _format_setting "HTTPS Proxy" "$(_npm_config_get https-proxy)"
    _format_setting "No Proxy" "$(_npm_config_get noproxy)"
    echo ""

    ux_section "Installation & Version"
    _format_setting "NPM Version" "$(npm --version 2>/dev/null || echo '[ERROR]')"
    _format_setting "Node Version" "$(node --version 2>/dev/null || echo '[ERROR]')"
    _format_setting "Prefix (Global Install)" "$(_npm_config_get prefix)"
    echo ""
}

check_npm_config_files() {
    ux_header "2. NPM Configuration Files"

    ux_section ".npmrc File (User Config)"
    if [ -f "$HOME/.npmrc" ]; then
        ux_success "Found: ~/.npmrc"
        ux_bullet "Size: $(wc -c < "$HOME/.npmrc") bytes"
        echo ""
        ux_section "Content:"
        cat "$HOME/.npmrc" | sed 's/^/    /'
        echo ""
    else
        ux_info "NOT FOUND: ~/.npmrc (using default or global config)"
        echo ""
    fi

    ux_section "npm.local.sh Status (Environment-specific)"
    local npm_local="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/integrations/npm.local.sh"
    if [ -f "$npm_local" ]; then
        ux_success "Found: npm.local.sh"
        echo ""

        if grep -q "^    DESIRED_REGISTRY=\"https://registry.npmjs.org/\"" "$npm_local"; then
            ux_info "Active Option: Option1 (External/VPN - npmjs + no proxy)"
        elif grep -q "^    DESIRED_REGISTRY=\"http://repo.samsungds.net" "$npm_local"; then
            ux_info "Active Option: Option2 (Internal PC - Artifactory + proxy)"
        fi
        echo ""
    else
        ux_warning "NOT FOUND: npm.local.sh"
        ux_info "This is normal - file is environment-specific and may not exist yet"
        ux_bullet "Run: ./setup.sh to configure npm.local.sh"
        echo ""
    fi
}

check_npm_environment() {
    ux_header "3. Environment Variables"

    ux_section "NPM-specific"
    _format_setting "NPM_CONFIG_PREFIX" "${NPM_CONFIG_PREFIX:-[NOT SET]}"
    _format_setting "NPM_CONFIG_REGISTRY" "${NPM_CONFIG_REGISTRY:-[NOT SET]}"
    echo ""

    ux_section "Proxy Settings"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "CA/SSL Settings"
    _format_setting "NODE_EXTRA_CA_CERTS" "${NODE_EXTRA_CA_CERTS:-[NOT SET]}"
    echo ""
}

check_npm_registry() {
    ux_header "4. Registry Connectivity Test"

    local registry
    registry=$(_npm_config_get registry)

    if [ "$registry" = "[NOT SET]" ]; then
        ux_warning "No registry configured"
        return 1
    fi

    ux_section "Testing Registry Access"
    ux_info "Registry: $registry"

    if timeout 5 npm ping 2>/dev/null; then
        ux_success "npm ping successful - Registry is accessible"
    else
        ux_warning "npm ping failed - Registry may not be accessible"
        ux_info "Possible causes:"
        ux_bullet "Network connectivity issue"
        ux_bullet "Registry URL is incorrect"
        ux_bullet "Proxy settings are misconfigured"
        ux_bullet "CA certificate validation failed"
    fi
    echo ""
}

check_npm_packages() {
    ux_header "5. Global Package Status"

    local prefix
    prefix=$(_npm_config_get prefix)

    if [ "$prefix" = "[NOT SET]" ]; then
        ux_warning "npm prefix not configured"
        return 1
    fi

    ux_section "Installation Directory"
    if [ -d "$prefix/lib/node_modules" ]; then
        ux_success "Found: $prefix/lib/node_modules"

        local count
        count=$(find "$prefix/lib/node_modules" -maxdepth 1 -type d | wc -l)
        count=$((count - 1))

        _format_setting "Total Packages Installed" "$count"
        _format_setting "Binary Directory" "$prefix/bin"

        if [ "$count" -gt 0 ]; then
            ux_bullet "Size: $(du -sh "$prefix/lib/node_modules" 2>/dev/null | cut -f1)"
        fi
        echo ""
    else
        ux_warning "NOT FOUND: $prefix/lib/node_modules"
        ux_info "No global packages installed yet"
        echo ""
    fi

    ux_section "Recent Packages (top 10)"
    if [ -d "$prefix/lib/node_modules" ]; then
        npm list -g --depth=0 2>/dev/null | head -15 || ux_warning "npm list failed"
    fi
    echo ""
}

# ============================================================
# Main function with sub-command handling
# ============================================================

main() {
    local cmd="${1:-all}"

    case "$cmd" in
        config)
            check_npm_config
            ;;
        files)
            check_npm_config_files
            ;;
        env)
            check_npm_environment
            ;;
        registry)
            check_npm_registry
            ;;
        packages)
            check_npm_packages
            ;;
        all)
            check_npm_config
            check_npm_config_files
            check_npm_environment
            check_npm_registry
            check_npm_packages
            ;;
        *)
            echo "Usage: check_npm [config|files|env|registry|packages|all]"
            echo ""
            echo "  config    - Show npm configuration"
            echo "  files     - Check npm config files"
            echo "  env       - Show environment variables"
            echo "  registry  - Test registry connectivity"
            echo "  packages  - Show installed global packages"
            echo "  all       - Run all checks (default)"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
