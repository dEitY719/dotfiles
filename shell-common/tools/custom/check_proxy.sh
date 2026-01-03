#!/bin/bash
# shell-common/tools/custom/check_proxy.sh
# Comprehensive proxy diagnostic script
# Usage: check_proxy [env|file|shell|conn|git|all]

# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    source "$(dirname "$0")/../ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ============================================================
# Helper functions
# ============================================================

_format_env() {
    local var="$1"
    local value="${2:-[NOT SET]}"
    printf "  %-20s : %s\n" "$var" "$value"
}

# ============================================================
# Diagnostic functions
# ============================================================

check_proxy_env() {
    ux_header "1. Current Environment Variables"

    ux_section "HTTP/HTTPS Proxy"
    _format_env "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_env "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_env "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_env "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"
    echo ""

    ux_section "NO Proxy (Exceptions)"
    if [ -n "$no_proxy" ]; then
        ux_bullet "no_proxy (lowercase) entries:"
        echo "$no_proxy" | tr ',' '\n' | sed 's/^/    - /'
    else
        ux_warning "no_proxy: [NOT SET]"
    fi
    echo ""
}

check_proxy_local_sh() {
    ux_header "2. proxy.local.sh Loading Status"

    ux_section "File Existence"
    if [ -f "$HOME/dotfiles/shell-common/env/proxy.local.sh" ]; then
        ux_success "proxy.local.sh exists"
        ux_bullet "Path: $HOME/dotfiles/shell-common/env/proxy.local.sh"
        ux_bullet "Size: $(wc -c < "$HOME/dotfiles/shell-common/env/proxy.local.sh") bytes"
        ux_bullet "Modified: $(stat -c '%y' "$HOME/dotfiles/shell-common/env/proxy.local.sh" 2>/dev/null || stat -f '%Sm' "$HOME/dotfiles/shell-common/env/proxy.local.sh" 2>/dev/null || echo '[N/A]')"
        echo ""

        ux_section "Content Validation"
        if grep -q "export http_proxy" "$HOME/dotfiles/shell-common/env/proxy.local.sh"; then
            ux_success "http_proxy export found"
        else
            ux_warning "http_proxy export not found"
        fi

        if grep -q "export no_proxy" "$HOME/dotfiles/shell-common/env/proxy.local.sh"; then
            ux_success "no_proxy export found"
        else
            ux_warning "no_proxy export not found"
        fi
    else
        ux_warning "proxy.local.sh NOT FOUND"
        ux_info "This is normal for public/home environments and VPN setups"
        ux_bullet "Option 1 (Public/Home PC): No proxy needed - file not required"
        ux_bullet "Option 2 (Internal PC): Run setup.sh and select option 2"
        ux_bullet "Option 3 (VPN): Uses direct connection - file not needed"
        ux_info "Continue with diagnostics for public/VPN environments..."
    fi
    echo ""
}

check_proxy_shell_loading() {
    ux_header "3. Shell Loading Test"

    ux_section "Bash"
    ux_info "Testing: bash -c 'source proxy.sh && echo \$http_proxy'"
    bash_result=$(bash -c "source $HOME/dotfiles/shell-common/env/proxy.sh 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
    if [ "$bash_result" != "[NOT SET]" ] && [ -n "$bash_result" ]; then
        ux_success "Bash loading: $bash_result"
    else
        ux_warning "Bash loading: [NOT SET] or failed"
    fi
    echo ""

    ux_section "Zsh"
    if command -v zsh >/dev/null 2>&1; then
        ux_info "Testing: zsh -c 'source proxy.sh && echo \$http_proxy'"
        zsh_result=$(zsh -c "source $HOME/dotfiles/shell-common/env/proxy.sh 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
        if [ "$zsh_result" != "[NOT SET]" ] && [ -n "$zsh_result" ]; then
            ux_success "Zsh loading: $zsh_result"
        else
            ux_warning "Zsh loading: [NOT SET] or failed"
        fi
    else
        ux_warning "Zsh not installed"
    fi
    echo ""
}

check_proxy_connectivity() {
    ux_header "4. Proxy Connectivity Test"

    if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
        ux_warning "No proxy configured, skipping connectivity test"
        echo ""
        return 0
    fi

    local proxy="${http_proxy:-$HTTP_PROXY}"

    ux_section "Connection Test (timeout 5s)"
    ux_bullet "Proxy: $proxy"
    ux_bullet "Target: https://github.com"
    echo ""

    if timeout 5 curl -v --proxy "$proxy" https://github.com 2>&1 | grep -q "HTTP\|Connected"; then
        ux_success "Proxy connection successful"
    else
        ux_error "Proxy connection failed or timeout"
    fi
    echo ""
}

check_git_config() {
    ux_header "5. Git Proxy Configuration"

    ux_section "Git Global Config"
    if git config --global -l | grep -q "proxy"; then
        ux_bullet "Git proxy configuration found:"
        git config --global -l | grep proxy | sed 's/^/  /'
    else
        ux_info "No explicit git proxy configuration (using system environment)"
    fi
    echo ""

    ux_section "Git Remote Access Test"
    ux_info "Testing: timeout 5 git ls-remote https://github.com/anthropics/claude-code.git"
    if timeout 5 git ls-remote https://github.com/anthropics/claude-code.git >/dev/null 2>&1; then
        ux_success "Git remote access successful"
    else
        ux_error "Git remote access failed"
    fi
    echo ""
}

# ============================================================
# Main function
# ============================================================

check_proxy() {
    local mode="${1:-all}"

    case "$mode" in
        env)
            check_proxy_env
            ;;
        file)
            check_proxy_local_sh
            ;;
        shell)
            check_proxy_shell_loading
            ;;
        conn|test)
            check_proxy_connectivity
            ;;
        git)
            check_git_config
            ;;
        all|*)
            check_proxy_env
            check_proxy_local_sh
            check_proxy_shell_loading
            check_proxy_connectivity
            check_git_config
            ;;
    esac

    ux_divider_thick
    echo ""
}

# ============================================================
# Execute if run directly (not sourced)
# ============================================================

if [ "${0##*/}" = "check_proxy.sh" ] || [ "$1" != "" ]; then
    check_proxy "$@"
fi
