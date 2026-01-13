#!/bin/bash
# shell-common/tools/external/npm.sh
# NPM/NVM 기본 설정 및 유틸리티
#
# 환경별 설정 방법:
#   1. NVM을 사용하는 경우 (집 또는 회사):
#      shell-common/tools/external/npm.local.example을 npm.local.sh로 복사
#   2. npm.local.sh에서 환경에 맞게 NPM/NVM 설정 수정
#   3. npm.local.sh는 자동으로 로드됨 (.gitignore에 의해 제외됨)
#
# 참고:
#   - 이 파일은 기본 NPM aliases와 helper functions만 제공합니다
#   - NVM 관련 설정은 npm.local.sh에서 처리해야 합니다
#   - npm.local.sh가 없으면 시스템에 설치된 기본 npm을 사용합니다

# ========================================
# Load UX Library
# ========================================
if ! declare -f ux_header >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/../tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ========================================
# NPM Aliases
# ========================================
alias npm-v='npm --version'
alias npm-outdated='npm outdated -g'
alias npm-update='npm update -g'
alias npm-cache-clean='npm cache clean --force'

# NPM Install Aliases
alias npm-i='npm install'
alias npm-is='npm install --save'
alias npm-isd='npm install --save-dev'
alias npm-ig='npm install -g'

# NPM Uninstall Aliases
alias npm-un='npm uninstall'
alias npm-ung='npm uninstall -g'

# NPM Info Function (with usage)
npm_info() {
    if [ -z "$1" ]; then
        echo "사용법: npm-info <package-name>"
        echo ""
        echo "예시:"
        echo "  npm-info react"
        echo "  npm-info lodash"
        echo "  npm-info express"
        return 1
    fi
    npm info "$@"
}
alias npm-info='npm_info'

# NPM Search Function (with usage)
npm_search() {
    if [ -z "$1" ]; then
        echo "사용법: npm-search <keyword>"
        echo ""
        echo "예시:"
        echo "  npm-search react"
        echo "  npm-search testing"
        echo "  npm-search animation"
        return 1
    fi
    npm search "$@"
}
alias npm-search='npm_search'

# NPM List Function (improved - shows multiple locations)
npm_list() {
    ux_header "NPM Packages Installed"

    ux_section "System Global NPM (/usr/lib)"
    npm list -g --depth=0 2>/dev/null | head -10 || ux_info "No global npm packages"
    echo ""

    ux_section "User Global (~/.npm-global/bin)"
    if [ -d "$HOME/.npm-global/bin" ]; then
        if [ "$(ls -1 "$HOME/.npm-global/bin" 2>/dev/null | wc -l)" -gt 0 ]; then
            ls -1 "$HOME/.npm-global/bin" 2>/dev/null | sed 's/^/  • /'
        else
            ux_info "No packages installed yet"
        fi
    else
        ux_warning "Directory not found: ~/.npm-global/bin"
    fi
    echo ""
}
alias npm-list='npm_list'

# ========================================
# NPM Configuration Apply (explicit)
# ========================================

_npm_apply_one() {
    local key="$1"
    local desired="${2-}"

    local current
    current="$(npm config get "$key" 2>/dev/null || true)"
    case "$current" in
        null | undefined) current="" ;;
    esac

    if [ "$current" = "$desired" ]; then
        ux_success "$key already set"
        return 0
    fi

    ux_info "Setting $key"
    if npm config set "$key" "$desired" >/dev/null 2>&1; then
        ux_success "$key updated"
        return 0
    fi

    ux_error "Failed to set $key"
    return 1
}

npm_apply_config() {
    if ! command -v npm >/dev/null 2>&1; then
        ux_error "npm not found"
        ux_info "Install: ${UX_BOLD}npminstall${UX_RESET}"
        return 1
    fi

    if [ -z "${DESIRED_REGISTRY:-}" ]; then
        ux_error "npm.local.sh not loaded (DESIRED_REGISTRY is empty)"
        ux_info "Create: ${UX_BOLD}shell-common/tools/integrations/npm.local.sh${UX_RESET}"
        ux_info "Or run: ${UX_BOLD}./shell-common/setup.sh${UX_RESET}"
        return 1
    fi

    ux_header "Apply npm config (explicit)"
    ux_info "This does not run automatically at shell init."

    _npm_apply_one "registry" "$DESIRED_REGISTRY" || return 1
    _npm_apply_one "cafile" "$DESIRED_CAFILE" || return 1
    _npm_apply_one "strict-ssl" "$DESIRED_STRICT_SSL" || return 1
    _npm_apply_one "proxy" "$DESIRED_PROXY" || return 1
    _npm_apply_one "https-proxy" "$DESIRED_HTTPS_PROXY" || return 1
    _npm_apply_one "noproxy" "$DESIRED_NOPROXY" || return 1
    _npm_apply_one "prefix" "$DESIRED_PREFIX" || return 1

    ux_success "npm config applied"
}
alias npm-apply-config='npm_apply_config'

# ========================================
# NPM Helper Function
# ========================================

# NPM 설치 (대화형 스크립트)
npminstall() {
    bash "$HOME/dotfiles/shell-common/tools/custom/install_npm.sh"
}

# NPM 제거 (대화형 스크립트)
npmuninstall() {
    bash "$HOME/dotfiles/shell-common/tools/custom/uninstall_npm.sh"
}

# ========================================
# CA Certificate Setup
# ========================================
# Note: Although CA certificate setup is placed here with npm utilities,
# it is actually managed by security.local.sh and provides broader functionality
# beyond npm (also used by Python via REQUESTS_CA_BUNDLE).
# This is a convenience location since npm often requires custom certificates.
# See crt-help for detailed CA certificate documentation.
crtsetup() {
    bash "$HOME/dotfiles/shell-common/tools/custom/setup_crt.sh"
}

# ========================================
# NPM PATH 설정
# ========================================
export PATH="$HOME/.npm-global/bin:$PATH"

# ========================================
# 환경별 로컬 NPM 설정 로드 (있는 경우)
# ========================================
if [ -f "${BASH_SOURCE[0]%/*}/npm.local.sh" ]; then
    . "${BASH_SOURCE[0]%/*}/npm.local.sh"
elif [ -f "${0:a:h}/npm.local.sh" ]; then
    # zsh support
    . "${0:a:h}/npm.local.sh"
fi
