#!/bin/sh
# shell-common/tools/integrations/npm.sh
# NPM aliases, helpers, and PATH setup
#
# Configuration:
#   ~/.npmrc is managed as a symlink to npm/npmrc.{environment}
#   Run ./shell-common/setup.sh to configure for your environment

# ========================================
# Load UX Library
# ========================================
if ! type ux_header >/dev/null 2>&1; then
    _npm_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_npm_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _npm_dir
fi

# ========================================
# NPM Aliases
# ========================================
alias npm-v='npm --version'
alias npm-outdated='npm outdated -g'
alias npm-update='npm update -g'
alias npm-cache-clean='npm cache clean --force'

# NPM Package Management Aliases
# shellcheck disable=SC2139  # aliases are intentionally lazy-evaluated
alias npm-i='npm i'
alias npm-is='npm i --save'
alias npm-isd='npm i --save-dev'
alias npm-ig='npm i -g'
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
# NPM Helper Function
# ========================================

# NPM 설치 (대화형 스크립트)
npminstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_npm.sh"
}

# NPM 제거 (대화형 스크립트)
npmuninstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/uninstall_npm.sh"
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
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/setup_crt.sh"
}

# ========================================
# NPM PATH 설정
# ========================================
export PATH="$HOME/.npm-global/bin:$PATH"

# ========================================
# NPM Configuration
# ========================================
# ~/.npmrc is managed as a symlink to npm/npmrc.{environment}
# Run ./shell-common/setup.sh to configure for your environment
