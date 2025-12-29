#!/bin/sh
# shell-common/tools/codex.sh
# Codex CLI - utilities and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation & Setup Guide
# ═══════════════════════════════════════════════════════════════

# 1) npm 전역 설치
#    npm config set prefix '~/.npm-global'
#    bash shell-common/tools/custom/install-codex.sh
#    또는 수동 설치:
#    npm install -g <codex-package-name>
#
# 2) API 키 또는 웹 로그인 인증
#    설정 파일 또는 환경 변수로 인증 필요
#    ~/.env 파일에 저장하거나, codex 명령어로 직접 인증

# ═══════════════════════════════════════════════════════════════
# Essential Command Aliases
# ═══════════════════════════════════════════════════════════════

alias cx='codex'                    # Basic command
alias cxhelp='codex --help'         # Show help
alias cxver='codex --version'       # Show version

# ═══════════════════════════════════════════════════════════════
# Codex Installation
# ═══════════════════════════════════════════════════════════════

cxinstall() {
    bash "${HOME}/dotfiles/shell-common/tools/custom/install-codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Uninstallation
# ═══════════════════════════════════════════════════════════════

cxuninstall() {
    bash "${HOME}/dotfiles/shell-common/tools/custom/uninstall-codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Status Check
# ═══════════════════════════════════════════════════════════════

cxstatus() {
    ux_header "Codex Status"

    if command -v codex > /dev/null 2>&1; then
        ux_success "Codex installed"
        ux_table_row "Version" "$(codex --version 2>/dev/null || echo 'unknown')" ""
        ux_table_row "Location" "$(which codex)" ""
    else
        ux_warning "Codex not found"
        ux_info "To install: bash shell-common/tools/custom/install-codex.sh"
        return 1
    fi

    echo ""
    ux_section "npm Global Packages"
    if ! npm list -g --depth=0 | grep -i codex > /dev/null 2>&1; then
        echo "  (No codex packages found)"
    fi
}
