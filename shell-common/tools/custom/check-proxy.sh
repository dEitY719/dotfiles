#!/bin/sh
# shell-common/tools/custom/check-proxy.sh
# Comprehensive proxy diagnostic script
# Usage: check_proxy [test|config|all]

set -e

# ============================================================
# Helper functions
# ============================================================

_print_header() {
    local title="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

_print_section() {
    echo ""
    echo "▶ $1"
}

_check_status() {
    if [ $? -eq 0 ]; then
        echo "  ✅ Success"
    else
        echo "  ❌ Failed"
    fi
}

_format_env() {
    local var="$1"
    local value="${2:-[NOT SET]}"
    printf "  %-20s : %s\n" "$var" "$value"
}

# ============================================================
# Diagnostic functions
# ============================================================

check_proxy_env() {
    _print_header "1. Current Environment Variables"

    echo ""
    _print_section "HTTP/HTTPS Proxy"
    _format_env "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_env "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_env "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_env "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"

    echo ""
    _print_section "NO Proxy (Exceptions)"
    if [ -n "$no_proxy" ]; then
        echo "  no_proxy (lowercase):"
        echo "$no_proxy" | tr ',' '\n' | sed 's/^/    - /'
    else
        echo "  ❌ no_proxy: [NOT SET]"
    fi
}

check_proxy_local_sh() {
    _print_header "2. proxy.local.sh Loading Status"

    _print_section "File Existence"
    if [ -f "$HOME/dotfiles/shell-common/env/proxy.local.sh" ]; then
        echo "  ✅ proxy.local.sh exists"
        echo "     Path: $HOME/dotfiles/shell-common/env/proxy.local.sh"
        echo "     Size: $(wc -c < "$HOME/dotfiles/shell-common/env/proxy.local.sh") bytes"
        echo "     Modified: $(stat -c '%y' "$HOME/dotfiles/shell-common/env/proxy.local.sh" 2>/dev/null || stat -f '%Sm' "$HOME/dotfiles/shell-common/env/proxy.local.sh" 2>/dev/null || echo '[N/A]')"
    else
        echo "  ❌ proxy.local.sh NOT FOUND"
        return 1
    fi

    _print_section "Content Validation"
    if grep -q "export http_proxy" "$HOME/dotfiles/shell-common/env/proxy.local.sh"; then
        echo "  ✅ http_proxy export found"
    else
        echo "  ⚠️  http_proxy export not found"
    fi

    if grep -q "export no_proxy" "$HOME/dotfiles/shell-common/env/proxy.local.sh"; then
        echo "  ✅ no_proxy export found"
    else
        echo "  ⚠️  no_proxy export not found"
    fi
}

check_proxy_shell_loading() {
    _print_header "3. Shell Loading Test"

    _print_section "Bash"
    echo "  Testing: bash -c 'source proxy.sh && echo \$http_proxy'"
    bash_result=$(bash -c "source $HOME/dotfiles/shell-common/env/proxy.sh 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
    if [ "$bash_result" != "[NOT SET]" ] && [ -n "$bash_result" ]; then
        echo "  ✅ Bash loading: $bash_result"
    else
        echo "  ⚠️  Bash loading: [NOT SET] or failed"
    fi

    _print_section "Zsh"
    if command -v zsh >/dev/null 2>&1; then
        echo "  Testing: zsh -c 'source proxy.sh && echo \$http_proxy'"
        zsh_result=$(zsh -c "source $HOME/dotfiles/shell-common/env/proxy.sh 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
        if [ "$zsh_result" != "[NOT SET]" ] && [ -n "$zsh_result" ]; then
            echo "  ✅ Zsh loading: $zsh_result"
        else
            echo "  ⚠️  Zsh loading: [NOT SET] or failed"
        fi
    else
        echo "  ⚠️  Zsh not installed"
    fi
}

check_proxy_connectivity() {
    _print_header "4. Proxy Connectivity Test"

    if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
        echo "⚠️  No proxy configured, skipping connectivity test"
        return 0
    fi

    local proxy="${http_proxy:-$HTTP_PROXY}"

    _print_section "Connection Test (timeout 5s)"
    echo "  Proxy: $proxy"
    echo "  Target: https://github.com"

    if timeout 5 curl -v --proxy "$proxy" https://github.com 2>&1 | grep -q "HTTP\|Connected"; then
        echo "  ✅ Proxy connection successful"
    else
        echo "  ❌ Proxy connection failed or timeout"
    fi
}

check_git_config() {
    _print_header "5. Git Proxy Configuration"

    _print_section "Git Global Config"
    if git config --global -l | grep -q "proxy"; then
        git config --global -l | grep proxy | sed 's/^/  /'
    else
        echo "  ℹ️  No explicit git proxy configuration (using system environment)"
    fi

    _print_section "Git Test"
    echo "  Testing: timeout 5 git ls-remote https://github.com/anthropics/claude-code.git"
    if timeout 5 git ls-remote https://github.com/anthropics/claude-code.git >/dev/null 2>&1; then
        echo "  ✅ Git remote access successful"
    else
        echo "  ❌ Git remote access failed"
    fi
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

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ============================================================
# Execute if run directly (not sourced)
# ============================================================

if [ "${0##*/}" = "check-proxy.sh" ] || [ "$1" != "" ]; then
    check_proxy "$@"
fi
