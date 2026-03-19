#!/bin/sh
# shell-common/functions/proxy_help.sh
# Proxy help function (bash/zsh compatible, uses local keyword)

proxy_help() {
    ux_header "Proxy Configuration & Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        ux_section "Diagnostic Commands"
        ux_bullet "check-proxy          Run full diagnostic"
        ux_bullet "check-proxy env      Environment variables only"
        ux_bullet "check-proxy file     proxy.local.sh file check"
        ux_bullet "check-proxy shell    Shell loading test"
        ux_bullet "check-proxy conn     Configured proxy connectivity test"
        ux_bullet "check-proxy git      Git configuration"


        ux_section "Quick Commands"
        ux_bullet "echo \$http_proxy          Current proxy setting"
        ux_bullet "echo \$https_proxy         Current HTTPS proxy"
        ux_bullet "echo \$no_proxy            NO_PROXY exceptions"
        ux_bullet "env | grep -i proxy        Show all proxy vars"


        ux_section "Setting Proxy (Corporate Environment)"
        ux_bullet "export http_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export https_proxy=\"http://proxy.example.com:8080/\""
        ux_bullet "export no_proxy=\"localhost,127.0.0.1,.internal.domain.com\""


        ux_section "Disabling Proxy"
        ux_bullet "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"


        ux_section "Git Configuration"
        ux_bullet "git config --global http.connectTimeout 60    Increase timeout"
        ux_bullet "git config --global http.lowSpeedLimit 0      Disable low speed limit"
        ux_bullet "git config --global http.lowSpeedTime 999999   Disable low speed time"
        ux_bullet "git config --global -l | grep proxy           View git proxy config"


        ux_section "Related Diagnostics"
        ux_bullet "check-network quick       General internet access check"
        ux_bullet "check-network             DNS, HTTPS, git, apt, pip, curl checks"


        ux_section "Important Notes"
        ux_warning "NO_PROXY with spaces is not recognized - use commas only"
        ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
        ux_info "check-proxy focuses on proxy configuration only"

    else
        # Fallback for minimal shells without UX library
        ux_header "Diagnostic Commands:"
        ux_bullet "check-proxy          Run full diagnostic"
        ux_bullet "check-proxy env      Environment variables only"
        ux_bullet "check-proxy file     proxy.local.sh file check"
        ux_bullet "check-network quick  General internet access check"

        ux_header "Quick Commands:"
        ux_bullet "echo \$http_proxy         Current proxy setting"
        ux_bullet "env | grep -i proxy      Show all proxy vars"

    fi
}

# Wrapper function for check_proxy.sh diagnostic
proxy_check() {
    local check_proxy_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_proxy.sh"
    if [ -f "$check_proxy_script" ]; then
        bash "$check_proxy_script" "$@"
    else
        # Error handling with fallback (guard ux_error)
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_proxy.sh not found at $check_proxy_script"
        else
            echo "Error: check_proxy.sh not found at $check_proxy_script" >&2
        fi
        return 1
    fi
}

# Aliases for proxy-help and check-proxy
alias proxy-help='proxy_help'
alias check-proxy='proxy_check'
