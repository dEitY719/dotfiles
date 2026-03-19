#!/bin/bash
# shell-common/tools/custom/check_nuget.sh
# Comprehensive NuGet configuration diagnostic script
# Usage: check_nuget [config|files|env|connectivity|all]

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

check_nuget_config() {
    ux_header "1. NuGet Configuration"

    ux_section "Tool Versions"
    if have_command dotnet; then
        _format_setting "dotnet Version" "$(dotnet --version 2>/dev/null || echo '[ERROR]')"
        _format_setting "dotnet Location" "$(command -v dotnet)"
    else
        ux_info "dotnet CLI not found in PATH"
    fi

    if have_command nuget; then
        _format_setting "nuget Version" "$(nuget help 2>/dev/null | head -1 || echo '[ERROR]')"
        _format_setting "nuget Location" "$(command -v nuget)"
    else
        ux_info "nuget CLI not found in PATH"
    fi

    if ! have_command dotnet && ! have_command nuget; then
        ux_warning "Neither dotnet nor nuget found in PATH"
        return 1
    fi
    echo ""

    ux_section "Configured Package Sources"
    if have_command dotnet; then
        dotnet nuget list source 2>/dev/null | sed 's/^/    /' || ux_warning "dotnet nuget list source failed"
    elif have_command nuget; then
        nuget sources list 2>/dev/null | sed 's/^/    /' || ux_warning "nuget sources list failed"
    fi
    echo ""
}

check_nuget_config_files() {
    ux_header "2. NuGet Configuration Files"

    # NuGet uses dual-path: ~/.nuget/NuGet/ (dotnet CLI) + ~/.config/NuGet/ (mono)
    local nuget_primary="$HOME/.nuget/NuGet/NuGet.Config"
    local nuget_secondary="$HOME/.config/NuGet/NuGet.Config"

    ux_section "Primary Path (~/.nuget/NuGet/NuGet.Config)"
    _check_nuget_file "$nuget_primary"

    ux_section "Secondary Path (~/.config/NuGet/NuGet.Config)"
    _check_nuget_file "$nuget_secondary"

    # Check consistency between the two paths
    if [ -f "$nuget_primary" ] && [ -f "$nuget_secondary" ]; then
        ux_section "Dual-Path Consistency"
        local target_primary target_secondary
        if [ -L "$nuget_primary" ]; then
            target_primary="$(readlink "$nuget_primary")"
        else
            target_primary="(regular file)"
        fi
        if [ -L "$nuget_secondary" ]; then
            target_secondary="$(readlink "$nuget_secondary")"
        else
            target_secondary="(regular file)"
        fi

        if [ "$target_primary" = "$target_secondary" ]; then
            ux_success "Both paths point to same target: $target_primary"
        else
            ux_warning "Paths point to different targets:"
            ux_bullet "Primary:   $target_primary"
            ux_bullet "Secondary: $target_secondary"
            ux_bullet "Fix: Run ./shell-common/setup.sh to reconfigure"
        fi
        echo ""
    fi
}

_check_nuget_file() {
    local conf_path="$1"
    local display_path
    display_path="$(echo "$conf_path" | sed "s|$HOME|~|")"

    if [ -L "$conf_path" ]; then
        local target
        target="$(readlink "$conf_path")"
        ux_success "Found: $display_path (symlink → $target)"

        case "$target" in
            *NuGet.Config.internal*) ux_info "Environment: Internal PC (DSNuget + nuget.org)" ;;
            *) ux_info "Environment: Unknown (custom symlink target)" ;;
        esac

        if [ -f "$conf_path" ]; then
            echo ""
            ux_section "Content:"
            sed 's/^/    /' "$conf_path"
        else
            ux_warning "Symlink target does not exist: $target"
            ux_bullet "Run: ./shell-common/setup.sh to reconfigure"
        fi
        echo ""
    elif [ -f "$conf_path" ]; then
        ux_warning "Found: $display_path (regular file, not symlink)"
        ux_bullet "Expected: symlink to dotfiles/nuget/NuGet.Config.{environment}"
        ux_bullet "Fix: Run ./shell-common/setup.sh to reconfigure"
        echo ""
        ux_section "Content:"
        sed 's/^/    /' "$conf_path"
        echo ""
    else
        ux_info "NOT FOUND: $display_path"
        echo ""
    fi
}

check_nuget_environment() {
    ux_header "3. Environment Variables"

    ux_section "NuGet Specific"
    _format_setting "NUGET_PACKAGES" "${NUGET_PACKAGES:-[NOT SET]}"
    _format_setting "NUGET_HTTP_CACHE_PATH" "${NUGET_HTTP_CACHE_PATH:-[NOT SET]}"
    _format_setting "DOTNET_ROOT" "${DOTNET_ROOT:-[NOT SET]}"
    echo ""

    ux_section "Proxy Settings"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""
}

check_nuget_connectivity() {
    ux_header "4. Source Connectivity Test"

    if ! have_command curl; then
        ux_warning "curl not found - skipping connectivity test"
        return 1
    fi

    # Collect source URLs: prefer dotnet CLI, fall back to NuGet.Config XML
    local sources=""

    if have_command dotnet; then
        sources=$(dotnet nuget list source 2>/dev/null | grep "http" | sed 's/.*\(http[^ ]*\).*/\1/')
    fi

    # Fallback: parse NuGet.Config XML directly (covers nuget-only environments)
    if [ -z "$sources" ]; then
        local nuget_conf=""
        if [ -f "$HOME/.nuget/NuGet/NuGet.Config" ]; then
            nuget_conf="$HOME/.nuget/NuGet/NuGet.Config"
        elif [ -f "$HOME/.config/NuGet/NuGet.Config" ]; then
            nuget_conf="$HOME/.config/NuGet/NuGet.Config"
        fi

        if [ -n "$nuget_conf" ]; then
            ux_info "Parsing source URLs from: $nuget_conf"
            sources=$(sed -n 's/.*value="\(http[^"]*\)".*/\1/p' "$nuget_conf")
        fi
    fi

    if [ -z "$sources" ]; then
        ux_info "No NuGet sources configured"
        return 0
    fi

    while read -r source_url; do
        if [ -z "$source_url" ]; then
            continue
        fi
        ux_section "Testing: $source_url"
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 "$source_url" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
            ux_success "Source accessible (HTTP $http_code)"
        else
            ux_warning "Source NOT accessible (HTTP $http_code)"
        fi
    done <<EOF
$sources
EOF
    echo ""
}

# ============================================================
# Main function with sub-command handling
# ============================================================

main() {
    local cmd="${1:-all}"

    case "$cmd" in
        config)
            check_nuget_config
            ;;
        files)
            check_nuget_config_files
            ;;
        env)
            check_nuget_environment
            ;;
        connectivity)
            check_nuget_connectivity
            ;;
        all)
            check_nuget_config
            check_nuget_config_files
            check_nuget_environment
            check_nuget_connectivity
            ;;
        *)
            echo "Usage: check_nuget [config|files|env|connectivity|all]"
            echo ""
            echo "  config        - Show NuGet version and sources"
            echo "  files         - Check NuGet config files (dual-path)"
            echo "  env           - Show environment variables"
            echo "  connectivity  - Test source connectivity"
            echo "  all           - Run all checks (default)"
            echo ""
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
