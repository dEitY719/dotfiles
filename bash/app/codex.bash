#!/bin/bash

: <<'CODEX_DOC'
==========================================================
Codex CLI Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (npm - 전역 패키지)
------------------------
# 1. npm 전역 경로 설정 (최초 1회, dotfiles에 이미 설정됨)
#    npm config set prefix '~/.npm-global'
# 2. 설치 스크립트 실행
#    bash mytool/install-codex.sh
#    또는 수동 설치:
#    npm install -g <codex-package-name>

2) API 키 or 웹 로그인 인증
------------------------
    설정 파일 또는 환경 변수로 인증 필요
    ~/.env 파일에 저장하거나,
    codex 명령어로 직접 인증

==========================================================
CODEX_DOC

# --- Alias 정의 ---
# Codex 기본 명령어
alias cx='codex'
alias cxhelp='codex --help'
alias cxver='codex --version'

# Codex 도움말 함수
codexhelp() {
    ux_header "Codex Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "cx" "codex" "Base command"
    ux_table_row "cxhelp" "codex --help" "Show help"
    ux_table_row "cxver" "codex --version" "Check version"
    echo ""

    ux_section "Installation & Setup"
    ux_table_row "cxinstall" "Install Script" "Install Codex CLI"
    ux_table_row "cxuninstall" "Uninstall Script" "Remove Codex CLI"
    echo ""

    ux_section "Interactive Mode"
    ux_table_row "cx" "codex" "Start interactive"
    ux_table_row "cx prompt" "codex prompt" "Run with prompt"
    echo ""

    ux_section "Tips"
    ux_bullet "Config: ~/.codex/ or ~/.config/codex/"
    ux_bullet "Auth: Use 'cx' to authenticate"
    echo ""
}

# Codex 설치 (대화형 스크립트)
cxinstall() {
    bash "$HOME/dotfiles/mytool/install-codex.sh"
}

# Codex 제거 (대화형 스크립트)
cxuninstall() {
    bash "$HOME/dotfiles/mytool/uninstall-codex.sh"
}

# Codex 버전 및 상태 확인
cxstatus() {
    ux_header "Codex Status"

    if command -v codex &>/dev/null; then
        ux_success "Codex installed"
        ux_table_row "Version" "$(codex --version 2>/dev/null || echo 'unknown')" ""
        ux_table_row "Location" "$(which codex)" ""
    else
        ux_warning "Codex not found"
        ux_info "To install: bash mytool/install-codex.sh"
        return 1
    fi

    echo ""
    ux_section "npm Global Packages"
    if ! npm list -g --depth=0 | grep -i codex; then
        echo "  (No codex packages found)"
    fi
}
