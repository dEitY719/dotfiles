#!/bin/sh
# shell-common/tools/integrations/agy.sh
# Antigravity CLI (agy) helper - shared across bash and zsh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

: <<'AGY_DOC'
==========================================================
Antigravity CLI (agy) Dotfiles Helper - Getting Started
==========================================================

1) 설치 (공식 스크립트)
------------------------
   curl -fsSL https://antigravity.google/cli/install.sh | bash
   Use: agy_install   (runs interactive installation script)
   Use: agy_uninstall (runs interactive uninstallation script)

2) 인증 / 사용
------------------------
   OAuth 토큰은 ~/.gemini/antigravity-cli/ 에 저장된다.
   Use: agyhelp   (agy --help — 실제 CLI 옵션 확인)
   Use: agymodels (agy models — 사용 가능한 모델 목록)

주의: agy 자체 인스톨러(agy install)는 셸 프로파일의 PATH/alias 를
수정한다. dotfiles 는 shell-common/env/path.sh 가 ~/.local/bin 을
PATH SSOT 로 관리하므로, agy install 을 직접 쓸 때는
--skip-path --skip-aliases 로 프로파일 오염을 막는 것을 권장한다.
==========================================================
AGY_DOC

# --- Aliases (agy --help 로 확인된 실제 플래그 기반) ---
alias agyver='agy --version'
alias agyhelp='agy --help'
alias agyc='agy --continue'
alias agyplan='agy --mode plan'
alias agymodels='agy models'

# --- Functions ---

# Antigravity CLI 설치 (대화형 스크립트)
agy_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_agy.sh"
}

# Antigravity CLI 제거 (대화형 스크립트)
agy_uninstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/uninstall_agy.sh"
}
