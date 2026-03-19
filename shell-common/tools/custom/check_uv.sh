#!/bin/bash
# shell-common/tools/custom/check_uv.sh
# Comprehensive uv configuration diagnostic script
# Usage: check_uv [config|files|env|connectivity|all]

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# ============================================================
# Helper functions
# ============================================================

_format_setting() {
    local label="$1"
    local value="${2:-[NOT SET]}"
    printf "  %-35s : %s\n" "$label" "$value"
}

# Read a key from uv.toml (TOML simple key = value parsing)
# uv has no CLI to query config; parse the file directly.
_uv_toml_get() {
    local key="$1"
    local uv_conf="$HOME/.config/uv/uv.toml"
    if [ -f "$uv_conf" ]; then
        # Match 'key = value' lines, strip quotes/brackets
        sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$uv_conf" | sed 's/^"//;s/"$//'
    fi
}

# ============================================================
# Diagnostic functions
# ============================================================

check_uv_config() {
    ux_header "1. UV Configuration"

    ux_section "Version & Location"
    if have_command uv; then
        _format_setting "uv Version" "$(uv --version 2>/dev/null || echo '[ERROR]')"
        _format_setting "uv Location" "$(command -v uv)"
    else
        ux_warning "uv not found in PATH"
        return 1
    fi

    ux_section "Active Settings (from ~/.config/uv/uv.toml)"
    local native_tls extra_index
    native_tls="$(_uv_toml_get native-tls)"
    extra_index="$(_uv_toml_get extra-index-url)"
    _format_setting "native-tls" "${native_tls:-[NOT SET]}"
    _format_setting "extra-index-url" "${extra_index:-[NOT SET]}"
    echo ""
}

check_uv_config_files() {
    ux_header "2. UV Configuration Files"

    local uv_conf="$HOME/.config/uv/uv.toml"

    ux_section "XDG Config Location"
    if [ -L "$uv_conf" ]; then
        local target
        target="$(readlink "$uv_conf")"
        ux_success "Found: ~/.config/uv/uv.toml (symlink → $target)"

        # Detect environment from symlink target
        case "$target" in
            *uv.toml.internal*) ux_info "Environment: Internal PC (Nexus + native-tls)" ;;
            *) ux_info "Environment: Unknown (custom symlink target)" ;;
        esac

        if [ -f "$uv_conf" ]; then
            echo ""
            ux_section "Content:"
            sed 's/^/    /' "$uv_conf"
        else
            ux_warning "Symlink target does not exist: $target"
            ux_bullet "Run: ./shell-common/setup.sh to reconfigure"
        fi
        echo ""
    elif [ -f "$uv_conf" ]; then
        ux_warning "Found: ~/.config/uv/uv.toml (regular file, not symlink)"
        ux_bullet "Expected: symlink to dotfiles/uv/uv.toml.{environment}"
        ux_bullet "Fix: Run ./shell-common/setup.sh to reconfigure"
        echo ""
        ux_section "Content:"
        sed 's/^/    /' "$uv_conf"
        echo ""
    else
        ux_info "NOT FOUND: ~/.config/uv/uv.toml (using default public PyPI)"
        ux_bullet "This is normal for external/public environments"
        ux_bullet "Run: ./shell-common/setup.sh to configure for internal use"
        echo ""
    fi
}

check_uv_environment() {
    ux_header "3. Environment Variables"

    ux_section "Proxy Settings (uv uses standard env vars)"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    _format_setting "NO_PROXY" "${NO_PROXY:-[NOT SET]}"
    echo ""

    ux_section "CA/SSL Settings"
    _format_setting "SSL_CERT_FILE" "${SSL_CERT_FILE:-[NOT SET]}"
    _format_setting "REQUESTS_CA_BUNDLE" "${REQUESTS_CA_BUNDLE:-[NOT SET]}"
    echo ""

    ux_section "UV Specific"
    _format_setting "UV_INDEX_URL" "${UV_INDEX_URL:-[NOT SET]}"
    _format_setting "UV_EXTRA_INDEX_URL" "${UV_EXTRA_INDEX_URL:-[NOT SET]}"
    _format_setting "UV_NATIVE_TLS" "${UV_NATIVE_TLS:-[NOT SET]}"
    echo ""
}

check_uv_connectivity() {
    ux_header "4. Repository Connectivity Test"

    if ! have_command curl; then
        ux_warning "curl not found - skipping connectivity test"
        return 1
    fi

    # Collect all configured index URLs from uv.toml and env vars
    local uv_conf="$HOME/.config/uv/uv.toml"
    local tested=0

    # 1) extra-index-url from uv.toml (the internal Nexus URL)
    if [ -f "$uv_conf" ]; then
        # Extract URLs from extra-index-url list (handles TOML array)
        local extra_urls
        extra_urls=$(sed -n 's/^extra-index-url[[:space:]]*=[[:space:]]*//p' "$uv_conf" \
            | tr -d '[]"' | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep "^http")

        if [ -n "$extra_urls" ]; then
            while read -r url; do
                if [ -z "$url" ]; then
                    continue
                fi
                ux_section "Extra Index: $url"
                local http_code
                http_code=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
                if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || [ "$http_code" = "404" ]; then
                    ux_success "Accessible (HTTP $http_code)"
                else
                    ux_warning "NOT accessible (HTTP $http_code)"
                    ux_info "Possible causes:"
                    ux_bullet "Network connectivity issue"
                    ux_bullet "Proxy settings are misconfigured"
                    ux_bullet "native-tls not enabled (required for corporate CA)"
                fi
                tested=$((tested + 1))
            done <<EOF
$extra_urls
EOF
        fi
    fi

    # 2) UV_EXTRA_INDEX_URL env var (overrides/supplements uv.toml)
    if [ -n "$UV_EXTRA_INDEX_URL" ]; then
        ux_section "Extra Index (env): $UV_EXTRA_INDEX_URL"
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 "$UV_EXTRA_INDEX_URL" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || [ "$http_code" = "404" ]; then
            ux_success "Accessible (HTTP $http_code)"
        else
            ux_warning "NOT accessible (HTTP $http_code)"
        fi
        tested=$((tested + 1))
    fi

    if [ "$tested" -eq 0 ]; then
        ux_info "No extra index URLs configured (using default public PyPI only)"
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
            check_uv_config
            ;;
        files)
            check_uv_config_files
            ;;
        env)
            check_uv_environment
            ;;
        connectivity)
            check_uv_connectivity
            ;;
        all)
            check_uv_config
            check_uv_config_files
            check_uv_environment
            check_uv_connectivity
            ;;
        *)
            echo "Usage: check_uv [config|files|env|connectivity|all]"
            echo ""
            echo "  config        - Show uv version and settings"
            echo "  files         - Check uv config files"
            echo "  env           - Show environment variables"
            echo "  connectivity  - Test repository connectivity"
            echo "  all           - Run all checks (default)"
            echo ""
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
