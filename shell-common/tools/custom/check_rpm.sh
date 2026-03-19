#!/bin/bash
# shell-common/tools/custom/check_rpm.sh
# Comprehensive RPM/YUM repository configuration diagnostic script
# Usage: check_rpm [config|files|env|connectivity|all]

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

_REPO_TARGET="/etc/yum.repos.d/ds.repo"
_MARKER="MANAGED_BY_DOTFILES"

# ============================================================
# Diagnostic functions
# ============================================================

check_rpm_config() {
    ux_header "1. RPM/YUM Configuration"

    ux_section "Package Manager"
    if have_command dnf; then
        _format_setting "dnf Version" "$(dnf --version 2>/dev/null | head -1 || echo '[ERROR]')"
        _format_setting "dnf Location" "$(command -v dnf)"
    elif have_command yum; then
        _format_setting "yum Version" "$(yum --version 2>/dev/null | head -1 || echo '[ERROR]')"
        _format_setting "yum Location" "$(command -v yum)"
    else
        ux_warning "Neither yum nor dnf found (not a RHEL/CentOS system)"
        return 1
    fi
    echo ""

    ux_section "OS Information"
    if [ -f /etc/os-release ]; then
        local os_id os_version os_name
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
        os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-}")"
        _format_setting "OS" "$os_name"
        _format_setting "ID" "$os_id"
        _format_setting "Version" "$os_version"
    else
        ux_info "/etc/os-release not found"
    fi
    echo ""

    ux_section "Repository List"
    if have_command yum; then
        yum repolist 2>/dev/null | sed 's/^/    /' || ux_warning "yum repolist failed"
    elif have_command dnf; then
        dnf repolist 2>/dev/null | sed 's/^/    /' || ux_warning "dnf repolist failed"
    fi
    echo ""
}

check_rpm_config_files() {
    ux_header "2. RPM Repository Files"

    ux_section "Dotfiles-managed Repo ($_REPO_TARGET)"

    if [ -f "$_REPO_TARGET" ]; then
        # Check for MANAGED_BY_DOTFILES marker
        if grep -q "$_MARKER" "$_REPO_TARGET" 2>/dev/null; then
            ux_success "Found: $_REPO_TARGET (managed by dotfiles)"
            ux_info "Marker: $_MARKER present"
        else
            ux_warning "Found: $_REPO_TARGET (NOT managed by dotfiles)"
            ux_bullet "File exists but missing $_MARKER marker"
            ux_bullet "May have been manually created or from another source"
        fi

        echo ""
        ux_section "Content:"
        sed 's/^/    /' "$_REPO_TARGET"
        echo ""

        # Compare with dotfiles source
        local source_file="${DOTFILES_ROOT}/rpm/ds.repo.internal"
        if [ -f "$source_file" ]; then
            ux_section "Drift Check"
            if diff -q "$_REPO_TARGET" "$source_file" >/dev/null 2>&1; then
                ux_success "Content matches dotfiles source"
            else
                ux_warning "Content differs from dotfiles source"
                ux_bullet "Source: $source_file"
                ux_bullet "Fix: Run ./shell-common/setup.sh to redeploy"
            fi
            echo ""
        fi
    else
        ux_info "NOT FOUND: $_REPO_TARGET"
        ux_bullet "This is normal for non-RHEL systems or external environments"
        ux_bullet "Run: ./shell-common/setup.sh to deploy for internal use"
        echo ""
    fi

    # Check for backup files
    ux_section "Backup Files"
    local backups
    backups=$(ls -1 "${_REPO_TARGET}.backup."* 2>/dev/null)
    if [ -n "$backups" ]; then
        echo "$backups" | while read -r backup; do
            ux_bullet "$backup"
        done
    else
        ux_info "No backup files found"
    fi
    echo ""
}

check_rpm_environment() {
    ux_header "3. Environment Variables"

    ux_section "Proxy Settings"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "YUM/DNF Settings"
    if [ -f /etc/yum.conf ]; then
        local yum_proxy
        yum_proxy=$(grep "^proxy" /etc/yum.conf 2>/dev/null | head -1)
        _format_setting "yum.conf proxy" "${yum_proxy:-[NOT SET]}"
    fi
    echo ""
}

check_rpm_connectivity() {
    ux_header "4. Repository Connectivity Test"

    if ! have_command yum && ! have_command dnf; then
        ux_warning "yum/dnf not found - skipping connectivity test"
        return 1
    fi

    ux_section "Repository Reachability"
    # Extract baseurl from the repo file
    if [ -f "$_REPO_TARGET" ]; then
        local base_urls
        base_urls=$(grep "^baseurl=" "$_REPO_TARGET" 2>/dev/null | cut -d= -f2)

        if [ -n "$base_urls" ]; then
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
$base_urls
EOF
        else
            ux_info "No baseurl found in repo file"
        fi
    else
        ux_info "No repo file found - skipping URL tests"
    fi
    echo ""

    ux_section "YUM Repolist Refresh"
    ux_info "Testing: yum repolist (may require sudo)"
    if have_command yum; then
        run_with_timeout 15 yum repolist 2>&1 | tail -5 | sed 's/^/    /' || ux_warning "yum repolist timed out or failed"
    elif have_command dnf; then
        run_with_timeout 15 dnf repolist 2>&1 | tail -5 | sed 's/^/    /' || ux_warning "dnf repolist timed out or failed"
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
            check_rpm_config
            ;;
        files)
            check_rpm_config_files
            ;;
        env)
            check_rpm_environment
            ;;
        connectivity)
            check_rpm_connectivity
            ;;
        all)
            check_rpm_config
            check_rpm_config_files
            check_rpm_environment
            check_rpm_connectivity
            ;;
        *)
            echo "Usage: check_rpm [config|files|env|connectivity|all]"
            echo ""
            echo "  config        - Show RPM/YUM version and repo list"
            echo "  files         - Check repo files and markers"
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
