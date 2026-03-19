#!/bin/bash
# shell-common/tools/custom/check_apt.sh
# Comprehensive APT sources configuration diagnostic script
# Usage: check_apt [config|files|env|connectivity|all]

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

_SOURCES_TARGET="/etc/apt/sources.list"
_MARKER="MANAGED_BY_DOTFILES"

# ============================================================
# Diagnostic functions
# ============================================================

check_apt_config() {
    ux_header "1. APT Configuration"

    ux_section "Package Manager"
    if have_command apt; then
        _format_setting "apt Version" "$(apt --version 2>/dev/null | head -1 || echo '[ERROR]')"
        _format_setting "apt Location" "$(command -v apt)"
    else
        ux_warning "apt not found (not a Debian/Ubuntu system)"
        return 1
    fi
    echo ""

    ux_section "OS Information"
    if [ -f /etc/os-release ]; then
        local os_id os_version os_codename os_name
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
        os_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
        os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-}")"
        _format_setting "OS" "$os_name"
        _format_setting "ID" "$os_id"
        _format_setting "Version" "$os_version"
        _format_setting "Codename" "$os_codename"
    else
        ux_info "/etc/os-release not found"
    fi
    echo ""
}

check_apt_config_files() {
    ux_header "2. APT Sources Files"

    ux_section "Main Sources ($_SOURCES_TARGET)"
    if [ -f "$_SOURCES_TARGET" ]; then
        # Check for MANAGED_BY_DOTFILES marker
        if grep -q "$_MARKER" "$_SOURCES_TARGET" 2>/dev/null; then
            ux_success "Found: $_SOURCES_TARGET (managed by dotfiles)"
            ux_info "Marker: $_MARKER present"
        else
            ux_warning "Found: $_SOURCES_TARGET (NOT managed by dotfiles)"
            ux_bullet "File exists but missing $_MARKER marker"
            ux_bullet "May be the system default or manually configured"
        fi

        echo ""
        ux_section "Content:"
        sed 's/^/    /' "$_SOURCES_TARGET"
        echo ""

        # Compare with dotfiles source
        local source_file="${DOTFILES_ROOT}/apt/sources.list.jammy.internal"
        if [ -f "$source_file" ]; then
            ux_section "Drift Check"
            if diff -q "$_SOURCES_TARGET" "$source_file" >/dev/null 2>&1; then
                ux_success "Content matches dotfiles source"
            else
                ux_warning "Content differs from dotfiles source"
                ux_bullet "Source: $source_file"
                ux_bullet "Fix: Run ./shell-common/setup.sh to redeploy"
            fi
            echo ""
        fi
    else
        ux_info "NOT FOUND: $_SOURCES_TARGET"
        ux_bullet "System may use /etc/apt/sources.list.d/ instead"
        echo ""
    fi

    # Check sources.list.d directory
    ux_section "Additional Sources (/etc/apt/sources.list.d/)"
    if [ -d /etc/apt/sources.list.d ]; then
        local count
        count=$(ls -1 /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            _format_setting "Additional source files" "$count"
            ls -1 /etc/apt/sources.list.d/ 2>/dev/null | sed 's/^/    /'
        else
            ux_info "No additional source files"
        fi
    else
        ux_info "Directory does not exist"
    fi
    echo ""

    # Check for backup files
    ux_section "Backup Files"
    local backups
    backups=$(ls -1 "${_SOURCES_TARGET}.backup."* 2>/dev/null)
    if [ -n "$backups" ]; then
        echo "$backups" | while read -r backup; do
            ux_bullet "$backup"
        done
    else
        ux_info "No backup files found"
    fi
    echo ""
}

check_apt_environment() {
    ux_header "3. Environment Variables"

    ux_section "Proxy Settings"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "APT Proxy Config"
    local apt_proxy_conf="/etc/apt/apt.conf.d/proxy.conf"
    if [ -f "$apt_proxy_conf" ]; then
        ux_info "Found: $apt_proxy_conf"
        sed 's/^/    /' "$apt_proxy_conf"
    else
        ux_info "No APT proxy config found at $apt_proxy_conf"
    fi

    # Also check generic apt.conf
    if [ -f /etc/apt/apt.conf ]; then
        local apt_proxy
        apt_proxy=$(grep -i "proxy" /etc/apt/apt.conf 2>/dev/null)
        if [ -n "$apt_proxy" ]; then
            _format_setting "apt.conf proxy" "$apt_proxy"
        fi
    fi
    echo ""
}

check_apt_connectivity() {
    ux_header "4. Repository Connectivity Test"

    if ! have_command apt; then
        ux_warning "apt not found - skipping connectivity test"
        return 1
    fi

    # Extract mirror URLs from sources.list
    if [ -f "$_SOURCES_TARGET" ]; then
        ux_section "Mirror URL Reachability"
        local urls
        urls=$(grep "^deb " "$_SOURCES_TARGET" 2>/dev/null | awk '{print $2}' | sort -u)

        if [ -n "$urls" ]; then
            while read -r url; do
                if [ -z "$url" ]; then
                    continue
                fi
                ux_info "Testing: $url"
                if have_command curl; then
                    local http_code
                    http_code=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
                    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
                        ux_success "  Accessible (HTTP $http_code)"
                    else
                        ux_warning "  NOT accessible (HTTP $http_code)"
                    fi
                fi
            done <<EOF
$urls
EOF
        else
            ux_info "No deb lines found in sources.list"
        fi
    else
        ux_info "No sources.list found - skipping URL tests"
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
            check_apt_config
            ;;
        files)
            check_apt_config_files
            ;;
        env)
            check_apt_environment
            ;;
        connectivity)
            check_apt_connectivity
            ;;
        all)
            check_apt_config
            check_apt_config_files
            check_apt_environment
            check_apt_connectivity
            ;;
        *)
            echo "Usage: check_apt [config|files|env|connectivity|all]"
            echo ""
            echo "  config        - Show APT version and OS info"
            echo "  files         - Check sources.list and markers"
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
