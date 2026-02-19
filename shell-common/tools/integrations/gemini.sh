#!/bin/sh
# shell-common/tools/external/gemini.sh
# Gemini CLI helper - shared across bash and zsh

: <<'GEMINI_DOC'
==========================================================
Gemini CLI Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (공식 GitHub: https://github.com/google/gemini-cli)
------------------------
   Use: ginstall (runs interactive installation script)
   Use: guninstall (runs interactive uninstallation script)

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

alias gemini-skip='gemini --yolo'
alias gemini-yolo='gemini --yolo'
