#!/bin/sh
# shell-common/functions/proxy_help.sh
# Proxy help function (POSIX-compatible, shared between bash and zsh)

proxy_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Proxy Configuration & Diagnostics"
    else
        echo ""
        echo "Proxy Configuration & Diagnostics"
        echo ""
    fi

    if type ux_section >/dev/null 2>&1; then
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

        ux_section "Setting Proxy (Corporate Environment)"
        ux_bullet "export http_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export https_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export no_proxy=\"localhost,127.0.0.1,.internal.domain.com\""
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

        ux_section "Important Notes"
        ux_warning "NO_PROXY with spaces is not recognized - use commas only"
        ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
        echo ""
    else
        # Fallback for minimal shells without UX library
        echo "Diagnostic Commands:"
        echo "  check-proxy          Run full diagnostic"
        echo "  check-proxy env      Environment variables only"
        echo "  check-proxy file     proxy.local.sh file check"
        echo ""
        echo "Quick Commands:"
        echo "  echo \$http_proxy         Current proxy setting"
        echo "  env | grep -i proxy      Show all proxy vars"
        echo ""
    fi
}

# Wrapper function for check_proxy.sh diagnostic
# Also runs pip_check for comprehensive network diagnostics
proxy_check() {
    local check_proxy_script="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/custom/check_proxy.sh"
    if [ -f "$check_proxy_script" ]; then
        bash "$check_proxy_script" "$@"
        echo ""
        echo ""
        # Also run pip check for comprehensive diagnostics
        if type pip_check >/dev/null 2>&1; then
            pip_check "$@"
        fi
    else
        ux_error "check_proxy.sh not found at $check_proxy_script" >&2
        return 1
    fi
}

# Aliases for proxy-help and check-proxy
alias proxy-help='proxy_help'
alias check-proxy='proxy_check'
