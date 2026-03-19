#!/bin/bash
# shell-common/tools/custom/check_proxy.sh
# Comprehensive proxy diagnostic script
# Usage: check_proxy [mode|env|file|shell|conn|git|all]

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
source "$(dirname "$0")/init.sh" || exit 1

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

check_setup_mode() {
    ux_header "0. Setup Mode Status"

    local setup_mode_file="$HOME/.dotfiles-setup-mode"
    if [ ! -f "$setup_mode_file" ]; then
        ux_warning "Setup mode not configured"
        ux_bullet "Run: ./setup.sh in ~/dotfiles to configure"
        echo ""
        return 0
    fi

    local mode
    mode=$(cat "$setup_mode_file" 2>/dev/null)

    case "$mode" in
        1)
            ux_success "Setup Mode: Public PC (Home environment)"
            ux_info "Expected behavior: NO proxy variables should be set"
            ;;
        2)
            ux_success "Setup Mode: Internal company PC (Direct connection)"
            ux_info "Expected behavior: Company proxy SHOULD be set (12.26.204.100:8080)"
            ;;
        3)
            ux_success "Setup Mode: External company PC (VPN)"
            ux_info "Expected behavior: NO proxy variables should be set"
            ;;
        *)
            ux_error "Unknown setup mode: $mode"
            ;;
    esac
    echo ""
}

get_setup_mode() {
    local setup_mode_file="$HOME/.dotfiles-setup-mode"
    if [ -f "$setup_mode_file" ]; then
        cat "$setup_mode_file" 2>/dev/null
    fi
}

check_proxy_env() {
    ux_header "1. Current Environment Variables"

    ux_section "HTTP/HTTPS Proxy"
    local has_proxy=0
    if [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        has_proxy=1
    fi

    _format_env "http_proxy" "${http_proxy:-[NOT SET]}"
    _format_env "HTTP_PROXY" "${HTTP_PROXY:-[NOT SET]}"
    _format_env "https_proxy" "${https_proxy:-[NOT SET]}"
    _format_env "HTTPS_PROXY" "${HTTPS_PROXY:-[NOT SET]}"

    # Validate against setup mode
    local mode
    mode="$(get_setup_mode)"
    case "$mode" in
        1|3)
            if [ "$has_proxy" -eq 1 ]; then
                echo ""
                ux_error "ISSUE DETECTED: Proxy is set but should not be (Mode $mode)"
                ux_info "This may be inherited from WSL or the system environment"
                ux_info "Solution: Restart your shell or run: source ~/.bashrc"
            fi
            ;;
        2)
            if [ "$has_proxy" -eq 0 ]; then
                echo ""
                ux_warning "No proxy set but Mode 2 (Internal PC) expects proxy"
                ux_info "Check if proxy.local.sh exists and is properly sourced"
            fi
            ;;
    esac
    echo ""

    ux_section "NO Proxy (Exceptions)"
    if [ -n "${no_proxy:-}" ]; then
        ux_bullet "no_proxy (lowercase) entries:"
        echo "$no_proxy" | tr ',' '\n' | sed 's/^/    - /'
    elif [ -n "${NO_PROXY:-}" ]; then
        ux_bullet "NO_PROXY (uppercase) entries:"
        echo "$NO_PROXY" | tr ',' '\n' | sed 's/^/    - /'
    else
        ux_warning "no_proxy: [NOT SET]"
    fi
    echo ""
}

check_proxy_local_sh() {
    ux_header "2. proxy.local.sh Loading Status"

    ux_section "File Existence"
    local proxy_local="${SHELL_COMMON}/env/proxy.local.sh"
    if [ -f "$proxy_local" ]; then
        ux_success "proxy.local.sh exists"
        ux_bullet "Path: $proxy_local"
        ux_bullet "Size: $(wc -c < "$proxy_local") bytes"
        ux_bullet "Modified: $(stat -c '%y' "$proxy_local" 2>/dev/null || stat -f '%Sm' "$proxy_local" 2>/dev/null || echo '[N/A]')"
        echo ""

        ux_section "Content Validation"
        if grep -q "export http_proxy" "$proxy_local"; then
            ux_success "http_proxy export found"
        else
            ux_warning "http_proxy export not found"
        fi

        if grep -q "export no_proxy" "$proxy_local"; then
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

    local proxy_sh="${SHELL_COMMON}/env/proxy.sh"
    local mode
    mode="$(get_setup_mode)"
    local bash_result=""
    local zsh_result=""
    local expected_proxy=0

    if [ "$mode" = "2" ]; then
        expected_proxy=1
    fi

    ux_section "Bash"
    ux_info "Testing: bash -c 'source proxy.sh && echo \$http_proxy'"
    bash_result=$(bash -c "source \"$proxy_sh\" 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
    if [ "$bash_result" != "[NOT SET]" ] && [ -n "$bash_result" ]; then
        ux_success "Bash loading: $bash_result"
    elif [ "$expected_proxy" -eq 1 ]; then
        ux_warning "Bash loading: proxy not loaded but Mode 2 expects one"
    else
        ux_success "Bash loading: no proxy configured (expected for this environment)"
    fi
    echo ""

    ux_section "Zsh"
    if command -v zsh >/dev/null 2>&1; then
        ux_info "Testing: zsh -c 'source proxy.sh && echo \$http_proxy'"
        zsh_result=$(zsh -c "source \"$proxy_sh\" 2>/dev/null && echo \${http_proxy:-[NOT SET]}" 2>/dev/null)
        if [ "$zsh_result" != "[NOT SET]" ] && [ -n "$zsh_result" ]; then
            ux_success "Zsh loading: $zsh_result"
        elif [ "$expected_proxy" -eq 1 ]; then
            ux_warning "Zsh loading: proxy not loaded but Mode 2 expects one"
        else
            ux_success "Zsh loading: no proxy configured (expected for this environment)"
        fi
    else
        ux_warning "Zsh not installed"
    fi
    echo ""
}

check_proxy_connectivity() {
    ux_header "4. Proxy Connectivity Test"

    local mode
    mode="$(get_setup_mode)"
    if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
        if [ "$mode" = "2" ]; then
            ux_warning "No proxy configured but Mode 2 expects one"
            ux_info "Check proxy.local.sh and shell loading diagnostics"
        else
            ux_info "No proxy configured, skipping proxy connectivity test"
            ux_info "Run check-network quick for general internet connectivity"
        fi
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
    ux_info "Testing: timeout 5 git ls-remote https://github.com/git/git.git HEAD"
    if timeout 5 git ls-remote https://github.com/git/git.git HEAD >/dev/null 2>&1; then
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
        mode)
            check_setup_mode
            ;;
        env)
            check_setup_mode
            check_proxy_env
            ;;
        file)
            check_setup_mode
            check_proxy_local_sh
            ;;
        shell)
            check_setup_mode
            check_proxy_shell_loading
            ;;
        conn|test)
            check_proxy_connectivity
            ;;
        git)
            check_git_config
            ;;
        all|*)
            check_setup_mode
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

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    check_proxy "$@"
fi
