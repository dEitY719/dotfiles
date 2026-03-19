#!/bin/bash
# shell-common/tools/custom/check_cargo.sh
# Comprehensive Cargo configuration diagnostic script
# Usage: check_cargo [config|files|env|connectivity|all]

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

# ============================================================
# Diagnostic functions
# ============================================================

check_cargo_config() {
    ux_header "1. Cargo Configuration"

    ux_section "Version & Location"
    if have_command cargo; then
        _format_setting "Cargo Version" "$(cargo --version 2>/dev/null || echo '[ERROR]')"
        _format_setting "Cargo Location" "$(command -v cargo)"
        _format_setting "Rustc Version" "$(rustc --version 2>/dev/null || echo '[NOT FOUND]')"
    else
        ux_warning "cargo not found in PATH"
        ux_bullet "Install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        return 1
    fi
    echo ""

    ux_section "Registry Settings"
    local cargo_conf="$HOME/.cargo/config.toml"
    if [ -f "$cargo_conf" ]; then
        # Extract registry info from config
        local default_reg
        default_reg=$(grep 'default\s*=' "$cargo_conf" 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/')
        _format_setting "Default Registry" "${default_reg:-[NOT SET]}"

        # Extract registry URLs
        local reg_index
        reg_index=$(grep 'index\s*=' "$cargo_conf" 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/')
        _format_setting "Registry Index URL" "${reg_index:-[NOT SET]}"

        # Check replace-with
        local replace_with
        replace_with=$(grep 'replace-with\s*=' "$cargo_conf" 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/')
        _format_setting "crates-io replace-with" "${replace_with:-[NOT SET]}"
    else
        ux_info "No config.toml found (using default crates.io)"
    fi
    echo ""
}

check_cargo_config_files() {
    ux_header "2. Cargo Configuration Files"

    local cargo_conf="$HOME/.cargo/config.toml"

    ux_section "Config File (~/.cargo/config.toml)"
    if [ -L "$cargo_conf" ]; then
        local target
        target="$(readlink "$cargo_conf")"
        ux_success "Found: ~/.cargo/config.toml (symlink → $target)"

        # Detect environment from symlink target
        case "$target" in
            *config.toml.internal*) ux_info "Environment: Internal PC (Nexus proxy for crates.io)" ;;
            *) ux_info "Environment: Unknown (custom symlink target)" ;;
        esac

        if [ -f "$cargo_conf" ]; then
            echo ""
            ux_section "Content:"
            sed 's/^/    /' "$cargo_conf"
        else
            ux_warning "Symlink target does not exist: $target"
            ux_bullet "Run: ./shell-common/setup.sh to reconfigure"
        fi
        echo ""
    elif [ -f "$cargo_conf" ]; then
        ux_warning "Found: ~/.cargo/config.toml (regular file, not symlink)"
        ux_bullet "Expected: symlink to dotfiles/cargo/config.toml.{environment}"
        ux_bullet "Fix: Run ./shell-common/setup.sh to reconfigure"
        echo ""
        ux_section "Content:"
        sed 's/^/    /' "$cargo_conf"
        echo ""
    else
        ux_info "NOT FOUND: ~/.cargo/config.toml (using default crates.io)"
        ux_bullet "This is normal for external/public environments"
        ux_bullet "Run: ./shell-common/setup.sh to configure for internal use"
        echo ""
    fi

    # Check for legacy config (without .toml extension)
    if [ -f "$HOME/.cargo/config" ]; then
        ux_section "Legacy Config"
        ux_warning "Found: ~/.cargo/config (legacy, may conflict with config.toml)"
        ux_bullet "Consider removing if config.toml is present"
        echo ""
    fi
}

check_cargo_environment() {
    ux_header "3. Environment Variables"

    ux_section "Cargo Specific"
    _format_setting "CARGO_HOME" "${CARGO_HOME:-[NOT SET] (default: ~/.cargo)}"
    _format_setting "CARGO_REGISTRIES_CRATES_IO_PROTOCOL" "${CARGO_REGISTRIES_CRATES_IO_PROTOCOL:-[NOT SET]}"
    _format_setting "CARGO_HTTP_PROXY" "${CARGO_HTTP_PROXY:-[NOT SET]}"
    _format_setting "CARGO_HTTP_CAINFO" "${CARGO_HTTP_CAINFO:-[NOT SET]}"
    echo ""

    ux_section "Proxy Settings (Cargo respects standard env vars)"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "Rust Toolchain"
    _format_setting "RUSTUP_HOME" "${RUSTUP_HOME:-[NOT SET] (default: ~/.rustup)}"
    _format_setting "RUSTUP_DIST_SERVER" "${RUSTUP_DIST_SERVER:-[NOT SET]}"
    echo ""
}

check_cargo_connectivity() {
    ux_header "4. Registry Connectivity Test"

    if ! have_command cargo; then
        ux_warning "cargo not found - skipping connectivity test"
        return 1
    fi

    ux_section "Crate Search Test"
    ux_info "Testing: cargo search serde --limit 1"

    local search_result
    search_result=$(run_with_timeout 15 cargo search serde --limit 1 2>&1)
    local rc=$?

    if [ $rc -eq 0 ] && echo "$search_result" | grep -q "serde"; then
        ux_success "cargo search successful - Registry is accessible"
        echo "  $search_result" | head -1
    else
        ux_warning "cargo search failed - Registry may not be accessible"
        ux_info "Possible causes:"
        ux_bullet "Network connectivity issue"
        ux_bullet "Registry URL is incorrect"
        ux_bullet "Proxy settings are misconfigured"
        ux_bullet "CA certificate validation failed"
        if [ -n "$search_result" ]; then
            echo ""
            ux_section "Error Output:"
            echo "$search_result" | head -5 | sed 's/^/    /'
        fi
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
            check_cargo_config
            ;;
        files)
            check_cargo_config_files
            ;;
        env)
            check_cargo_environment
            ;;
        connectivity)
            check_cargo_connectivity
            ;;
        all)
            check_cargo_config
            check_cargo_config_files
            check_cargo_environment
            check_cargo_connectivity
            ;;
        *)
            echo "Usage: check_cargo [config|files|env|connectivity|all]"
            echo ""
            echo "  config        - Show Cargo version and settings"
            echo "  files         - Check Cargo config files"
            echo "  env           - Show environment variables"
            echo "  connectivity  - Test registry connectivity"
            echo "  all           - Run all checks (default)"
            echo ""
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
