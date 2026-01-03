#!/bin/bash
# proxy.sh
# Proxy configuration and diagnostics (environment-agnostic)
#
# This file provides:
#   1. Default proxy settings (works in all environments)
#   2. proxy_help() function (available in all environments)
#   3. check-proxy alias (diagnostic tool)
#   4. Loading of environment-specific proxy.local.sh (if exists)
#
# Environment-specific proxy settings are in:
#   - proxy.local.example (template)
#   - proxy.local.sh (auto-generated, environment-specific)

# Load UX library if not already loaded (for proxy_help() formatting)
if ! declare -f ux_header >/dev/null 2>&1; then
    source "${BASH_SOURCE[0]%/*}/../tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ============================================================
# DEFAULT SETTINGS (for public/home environment)
# ============================================================

# No Proxy 설정 (기본값 - 일반 가정 환경)
export no_proxy="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.local"
export NO_PROXY="$no_proxy"

# HTTP/HTTPS 프록시 설정 (필요한 경우 override됨)
# export http_proxy="http://proxy.example.com:8080"
# export https_proxy="http://proxy.example.com:8080"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"

# ============================================================
# HELP & DIAGNOSTICS (environment-agnostic)
# ============================================================

proxy_help() {
    ux_header "Proxy(Corporate) Commands & Diagnostics"

    ux_section "Diagnostic Commands"
    ux_bullet "check-proxy          Run full diagnostic"
    ux_bullet "check-proxy env      Environment variables only"
    ux_bullet "check-proxy file     proxy.local.sh file check"
    ux_bullet "check-proxy shell    Shell loading test"
    ux_bullet "check-proxy conn     Connectivity test"
    ux_bullet "check-proxy git      Git configuration"
    echo ""

    ux_section "Quick Commands"
    ux_bullet "echo \$http_proxy          Current proxy setting"
    ux_bullet "echo \$https_proxy         Current HTTPS proxy"
    ux_bullet "echo \$no_proxy            NO_PROXY exceptions"
    ux_bullet "env | grep -i proxy        Show all proxy vars"
    echo ""

    ux_section "Setting Proxy (Company Internal)"
    ux_bullet "export http_proxy=\"http://12.26.204.100:8080/\""
    ux_bullet "export https_proxy=\"http://12.26.204.100:8080/\""
    ux_bullet "export no_proxy=\"10.229.95.200,10.229.95.220,12.36.155.91,12.36.154.116,12.36.154.130,localhost,127.0.0.1,.samsung.net,.samsungds.net,ssai.samsungds.net,dsvdi.net,pfs.nprotect.com\""
    echo ""

    ux_section "Disabling Proxy"
    ux_bullet "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
    echo ""

    ux_section "Git Configuration"
    ux_bullet "git config --global http.connectTimeout 60    Increase timeout"
    ux_bullet "git config --global http.lowSpeedLimit 0      Disable low speed limit"
    ux_bullet "git config --global http.lowSpeedTime 999999   Disable low speed time"
    ux_bullet "git config --global -l | grep proxy           View git proxy config"
    echo ""

    ux_section "GitHub Bypass (Direct Connection)"
    ux_bullet "git config --global url.\"https://github.com/\".insteadOf https://"
    echo ""

    ux_section "Common Recipes"
    ux_numbered "1" "Temporary proxy (current session only): export http_proxy=\"http://12.26.204.100:8080/\""
    ux_numbered "2" "Add exception for domain: export no_proxy=\"\$no_proxy,.internal.domain.com\""
    ux_numbered "3" "Complete reset: unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
    echo ""

    ux_section "Important Notes"
    ux_warning "NO_PROXY with spaces is not recognized - use commas only"
    ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
    ux_info "Reference: https://confluence.samsungds.net/pages/viewpage.action?pageId=1367083095"
    echo ""
}

# Wrapper function for check-proxy.sh
proxy_check() {
    if [ -f "${HOME}/dotfiles/shell-common/tools/custom/check-proxy.sh" ]; then
        bash "${HOME}/dotfiles/shell-common/tools/custom/check-proxy.sh" "$@"
    else
        echo "❌ check-proxy.sh not found at ~/dotfiles/shell-common/tools/custom/check-proxy.sh"
        return 1
    fi
}

# Aliases (both work in interactive shells)
alias proxy-help='proxy_help'
alias check-proxy='proxy_check'

# ============================================================
# ENVIRONMENT-SPECIFIC SETTINGS (loaded if exists)
# ============================================================

# Load environment-specific proxy configuration (if exists)
# This allows overriding default settings for specific environments
if [ -f "${BASH_SOURCE[0]%/*}/proxy.local.sh" ]; then
    . "${BASH_SOURCE[0]%/*}/proxy.local.sh"
elif [ -f "${0:a:h}/proxy.local.sh" ]; then
    # zsh support
    . "${0:a:h}/proxy.local.sh"
fi
