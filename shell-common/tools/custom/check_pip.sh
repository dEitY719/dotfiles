#!/bin/bash
# shell-common/tools/custom/check_pip.sh
# Comprehensive pip configuration diagnostic script
# Usage: check_pip [config|file|repo|env|all]

# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    source "$(dirname "$0")/../ux_lib/ux_lib.sh" 2>/dev/null || true
fi

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

check_pip_config() {
    ux_header "1. Pip Configuration"

    ux_section "Loaded Configuration"
    pip config list 2>/dev/null || ux_warning "pip config list failed"
    echo ""
}

check_pip_config_files() {
    ux_header "2. Pip Configuration Files"

    ux_section "XDG Config Location (Primary)"
    if [ -f "$HOME/.config/pip/pip.conf" ]; then
        ux_success "Found: ~/.config/pip/pip.conf"

        if [ -L "$HOME/.config/pip/pip.conf" ]; then
            local target
            target=$(readlink "$HOME/.config/pip/pip.conf")
            ux_info "Type: Symlink"
            ux_bullet "Target: $target"
            if [ -f "$target" ]; then
                ux_success "Target exists"
            else
                ux_warning "Target NOT FOUND"
            fi
        else
            ux_info "Type: Regular file"
        fi

        ux_bullet "Size: $(wc -c < "$HOME/.config/pip/pip.conf") bytes"
        echo ""
        ux_section "Content:"
        cat "$HOME/.config/pip/pip.conf" | sed 's/^/    /'
        echo ""
    else
        ux_warning "NOT FOUND: ~/.config/pip/pip.conf"
        echo ""
    fi

    ux_section "Legacy Config Location (if exists)"
    if [ -f "$HOME/.pip/pip.conf" ]; then
        ux_warning "FOUND: ~/.pip/pip.conf (legacy location - may override XDG)"
        ux_bullet "Size: $(wc -c < "$HOME/.pip/pip.conf") bytes"
        echo ""
    else
        ux_success "NOT FOUND: ~/.pip/pip.conf (good - no conflict)"
        echo ""
    fi
}

check_pip_environment() {
    ux_header "3. Environment Variables"

    ux_section "Proxy Settings"
    _format_setting "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_setting "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_setting "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_setting "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "CA/SSL Settings"
    _format_setting "REQUESTS_CA_BUNDLE" "${REQUESTS_CA_BUNDLE:-[NOT SET]}"
    _format_setting "NODE_EXTRA_CA_CERTS" "${NODE_EXTRA_CA_CERTS:-[NOT SET]}"
    _format_setting "PIP_CERT" "${PIP_CERT:-[NOT SET]}"
    echo ""

    ux_section "Pip Specific"
    _format_setting "PIP_INDEX_URL" "${PIP_INDEX_URL:-[NOT SET]}"
    _format_setting "PIP_EXTRA_INDEX_URL" "${PIP_EXTRA_INDEX_URL:-[NOT SET]}"
    _format_setting "PIP_CONFIG_FILE" "${PIP_CONFIG_FILE:-[NOT SET]}"
    echo ""
}

check_pip_repository() {
    ux_header "4. Repository Connectivity Test"

    ux_section "Primary Repository"
    local repo_url="http://repo.samsungds.net:8081/artifactory/api/pypi/pypi/simple"
    echo "  Testing: $repo_url"

    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 5 --max-time 10 "$repo_url" >/dev/null 2>&1; then
            ux_success "Repository accessible (HTTP)"
        else
            ux_warning "Repository NOT accessible (may require proxy/authentication)"
        fi
    else
        ux_info "curl not available - skipping connectivity test"
    fi
    echo ""

    ux_section "Secondary Repository (DataService)"
    local secondary_url="http://nexus.adpaas.cloud.samsungds.net/repository/dataservice-pypi/simple"
    echo "  Testing: $secondary_url"

    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 5 --max-time 10 "$secondary_url" >/dev/null 2>&1; then
            ux_success "Repository accessible (HTTP)"
        else
            ux_warning "Repository NOT accessible (may require proxy/authentication)"
        fi
    else
        ux_info "curl not available - skipping connectivity test"
    fi
    echo ""
}

check_pip_version() {
    ux_header "5. Pip Version & Python Info"

    ux_section "Pip Version"
    pip --version || ux_warning "pip --version failed"
    echo ""

    ux_section "Python Information"
    python --version 2>/dev/null || python3 --version || ux_warning "Python not found"
    echo ""

    ux_section "Installation Paths"
    if command -v pip >/dev/null 2>&1; then
        ux_bullet "pip location: $(command -v pip)"
    fi
    if command -v python >/dev/null 2>&1; then
        ux_bullet "python location: $(command -v python)"
    fi
    echo ""
}

check_all() {
    check_pip_config
    check_pip_config_files
    check_pip_environment
    check_pip_repository
    check_pip_version
}

# ============================================================
# Main
# ============================================================

case "${1:-all}" in
    config)
        check_pip_config
        ;;
    file)
        check_pip_config_files
        ;;
    env)
        check_pip_environment
        ;;
    repo)
        check_pip_repository
        ;;
    all|*)
        check_all
        ;;
esac
