#!/bin/sh
# shell-common/tools/integrations/uv.sh
# uv (Python package manager) aliases (POSIX-compatible).
# Help: `uv-help` (defined in shell-common/functions/package_managers_help.sh)
# lists every uv* alias below.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ── 기본 동사 규칙 ──────────────────────────────────────────────
# uvi : install (툴 설치)
# uvs : sync (환경 동기화)
# uvu : sync with upgrade
# uvl : lock (lock 갱신)
# uvc : compile/export (reqs 생성)
# uvr : requirements로 sync
# uvd : dev용 설치
# uvp : prod용 설치
# uvclean : 불필요 패키지 정리 (사실상 uvs와 동일)
# uvh : help

# (1) uv 자체 설치

# (2) 가장 자주 쓰는 것들
alias uvs='uv sync'                   # 기본/프로덕션 동기화 (설치 및 정리 포함)
alias uvu='uv sync --upgrade'         # 업그레이드 동기화
alias uvd='uv sync --dev --extra dev' # dev 환경 설치
alias uvk='uv lock'                   # lock 파일 갱신
alias uvl='uv pip list'               # 설치 목록 확인

# (3) export / requirements 기반 sync
alias uvc='uv pip compile pyproject.toml -o requirements.txt'
alias uvr='uv pip sync requirements.txt'

# (5) 상태/검증
alias uvcheck='uv pip check'

# (6) uv-install 함수 (shell-common/tools/custom/install_uv.sh 호출)
# POSIX requires function names match [a-zA-Z_][a-zA-Z0-9_]*; expose the dashed
# form as an alias to keep the same user-facing command name.
uv_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_uv.sh"
}
alias uv-install='uv_install'

# (7) 도움말: `uv-help` (registered in package_managers_help.sh)
