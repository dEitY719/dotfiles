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
    ux_header "Gemini CLI Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "gg" "gcloud gemini" "Base command"
    ux_table_row "gflash" "gemini --model flash" "Use Flash model"
    ux_table_row "gpro" "gemini --model pro" "Use Pro model"
    ux_table_row "gver" "gemini --version" "Check version"
    ux_table_row "ghelp" "gemini --help" "Gemini Help"
    echo ""

    ux_section "Installation & Setup"
    ux_table_row "ginstall" "Install Script" "Install Gemini CLI"
    ux_table_row "guninstall" "Uninstall Script" "Remove Gemini CLI"
    echo ""

    ux_section "Tips"
    ux_bullet "Auth via web login (no API key file needed)"
    ux_bullet "Use 'ghelp' for detailed CLI options"
    echo ""
}

# Gemini 설치 (대화형 스크립트)
ginstall() {
    bash /home/bwyoon/dotfiles/mytool/install-gemini.sh
}

# Gemini 제거 (대화형 스크립트)
guninstall() {
    bash /home/bwyoon/dotfiles/mytool/uninstall-gemini.sh
}
