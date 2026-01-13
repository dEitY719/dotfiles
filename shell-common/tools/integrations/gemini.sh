#!/bin/bash
# shell-common/tools/external/gemini.sh
# Gemini CLI helper - shared across bash and zsh

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

# --- Aliases ---
alias gg='gcloud gemini'
alias gflash='gemini --model gemini-2.5-flash'
alias gpro='gemini --model gemini-2.5-pro'
alias gver='gemini --version'
alias ghelp='gemini --help'

# --- Functions ---

# Gemini 설치 (대화형 스크립트)
ginstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_gemini.sh"
}

# Gemini 제거 (대화형 스크립트)
guninstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/uninstall_gemini.sh"
}
