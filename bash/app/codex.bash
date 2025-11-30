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
    # Color definitions
    local bold blue green reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[Codex Quick Commands]${reset}

  ${bold}${blue}Basic Commands:${reset}
    ${green}cx${reset}         : codex (기본 명령어)
    ${green}cxhelp${reset}     : codex --help (도움말)
    ${green}cxver${reset}      : codex --version (버전 정보)

  ${bold}${blue}Installation & Setup:${reset}
    ${green}cxinstall${reset}  : Codex CLI 설치 (대화형 스크립트)

  ${bold}${blue}Interactive Mode:${reset}
    ${green}cx${reset}         : 대화형 모드 시작
    ${green}cx prompt${reset}  : 프롬프트와 함께 실행

  ${bold}${blue}Tips:${reset}
    • 설치: cxinstall
    • 설정: ~/.codex/ 또는 ~/.config/codex/
    • API 인증: codex 명령어로 직접 설정
    • 더 많은 기능은 'cxhelp' 참고

EOF
}

# Codex 설치 (대화형 스크립트)
cxinstall() {
    bash /home/bwyoon/dotfiles/mytool/install-codex.sh
}

# Codex 제거 (대화형 스크립트)
cxuninstall() {
    bash /home/bwyoon/dotfiles/mytool/uninstall-codex.sh
}

# Codex 버전 및 상태 확인
cxstatus() {
    local bold blue green yellow reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    echo "${bold}${blue}=== Codex Status ===${reset}"
    echo ""

    if command -v codex &>/dev/null; then
        echo "${bold}${green}✓ Codex installed${reset}"
        echo "  Version: $(codex --version 2>/dev/null || echo 'unknown')"
        echo "  Location: $(which codex)"
    else
        echo "${bold}${yellow}⚠ Codex not found${reset}"
        echo "  설치: bash mytool/install-codex.sh"
        return 1
    fi

    echo ""
    echo "${bold}npm Global Packages:${reset}"
    npm list -g --depth=0 | grep -i codex || echo "  (No codex packages found)"
}
