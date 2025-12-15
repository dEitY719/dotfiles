#!/bin/bash
# bash/app/uv.bash  (정리판)

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

# (6) uv-install 함수 (mytool/install-uv.sh 호출)
uv-install() {
    bash "$HOME/dotfiles/mytool/install-uv.sh"
}

# (7) 도움말(프로젝트 관례 안내)
uvhelp() {
    ux_header "UV Quick Commands"

    ux_section "Sync & Install"
    ux_table_row "uvs" "uv sync" "Sync env & prune (Prod)"
    ux_table_row "uvu" "uv sync --upgrade" "Upgrade deps"
    ux_table_row "uvd" "uv sync --dev" "Dev install"
    ux_table_row "uv-install" "install script" "Install UV tool"
    echo ""

    ux_section "Lock & Export"
    ux_table_row "uvk" "uv lock" "Refresh lockfile"
    ux_table_row "uvl" "uv pip list" "List packages"
    ux_table_row "uvc" "uv pip compile" "Export requirements"
    ux_table_row "uvr" "uv pip sync" "Sync from reqs"
    echo ""

    ux_section "Maintenance"
    ux_table_row "uvcheck" "uv pip check" "Verify env"
    echo ""

    ux_section "Recipes"
    ux_bullet "Install all extras: ${UX_SUCCESS}uv pip sync --all-extras${UX_RESET}"
    ux_bullet "Backend dev:      ${UX_SUCCESS}uv pip sync --extra backend --extra dev${UX_RESET}"
    ux_bullet "Frontend dev:     ${UX_SUCCESS}uv pip sync --extra frontend --extra dev${UX_RESET}"
    echo ""
}
