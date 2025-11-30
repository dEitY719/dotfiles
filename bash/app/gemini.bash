#!/bin/bash

: <<'GEMINI_DOC'
==========================================================
Gemini CLI Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (npm - 공식 gcloud CLI 확장)
------------------------
# 1. npm 전역 경로 설정 (최초 1회, dotfiles에 이미 설정됨)
#    npm config set prefix '~/.npm-global'
# 2. 설치 (공식 GitHub: https://github.com/google/gemini-cli)
#    npm install -g @google/gemini-cli

2) API 키 or 웹 로그인 인증
------------------------
    ~/.env 파일에 저장된 GEMINI_API_KEY는 쓸모없고, 
    웹 로그인으로 인증 완료
==========================================================
GEMINI_DOC

# --- 별칭(Alias) 및 함수 정의 ---
# gcloud-based Gemini CLI alias (separate tool)
alias gg='gcloud gemini'
alias gflash='gemini --model gemini-2.5-flash'
alias gpro='gemini --model gemini-2.5-pro'
alias gver='gemini --version'
alias ghelp='gemini --help'

# Gemini 도움말 함수
geminihelp() {
    # Color definitions
    local bold blue green reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[Gemini CLI Quick Commands]${reset}

  ${bold}${blue}Basic Commands:${reset}
    ${green}gg${reset}           : gcloud gemini (기본 명령어)
    ${green}gflash${reset}       : gemini --model gemini-2.5-flash
    ${green}gpro${reset}         : gemini --model gemini-2.5-pro
    ${green}gver${reset}         : gemini --version (버전 정보)
    ${green}ghelp${reset}        : gemini --help (도움말)

  ${bold}${blue}Installation & Setup:${reset}
    ${green}ginstall${reset}     : Gemini CLI 설치 (대화형 스크립트)
    ${green}guninstall${reset}   : Gemini CLI 제거 (대화형 스크립트)

  ${bold}${blue}Tips:${reset}
    • 설치: ginstall
    • 웹 로그인으로 인증 완료
    • 더 많은 기능은 'ghelp' 참고

EOF
}

# Gemini 설치 (대화형 스크립트)
ginstall() {
    bash /home/bwyoon/dotfiles/mytool/install-gemini.sh
}

# Gemini 제거 (대화형 스크립트)
guninstall() {
    bash /home/bwyoon/dotfiles/mytool/uninstall-gemini.sh
}
