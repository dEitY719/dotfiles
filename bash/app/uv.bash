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
alias uvi='curl -LsSf https://astral.sh/uv/install.sh | sh'

# (2) 가장 자주 쓰는 것들
alias uvs='uv sync'                   # 기본/프로덕션 동기화
alias uvu='uv sync --upgrade'         # 업그레이드 동기화
alias uvd='uv sync --dev --extra dev' # dev 환경 설치
alias uvp='uv sync'                   # prod 동기화(=uvs)
alias uvk='uv lock'                   # lock 파일 갱신
alias uvl='uv pip list'               # 설치 목록 확인

# (3) export / requirements 기반 sync
alias uvc='uv pip compile pyproject.toml -o requirements.txt'
alias uvr='uv pip sync requirements.txt'

# (4) 클린 동기화 (여분 패키지 제거, 기본 동작과 동일)
alias uvclean='uv sync --clean'

# (5) 상태/검증
alias uvcheck='uv pip check'

# (6) 도움말(프로젝트 관례 안내)
uvhelp() {
    # Color definitions
    local bold=$(tput bold 2>/dev/null || echo "")
    local blue=$(tput setaf 4 2>/dev/null || echo "")
    local green=$(tput setaf 2 2>/dev/null || echo "")
    local reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[UV Quick Commands]${reset}

  ${green}uvs${reset}        : uv sync (base/prod)
  ${green}uvu${reset}        : uv sync --upgrade (업그레이드 동기화)
  ${green}uvd${reset}        : uv sync --dev --extra dev
  ${green}uvp${reset}        : uv sync (prod)
  ${green}uvk${reset}        : uv lock
  ${green}uvl${reset}        : uv pip list
  ${green}uvc${reset}        : uv pip compile pyproject.toml -o requirements.txt
  ${green}uvr${reset}        : uv pip sync requirements.txt
  ${green}uvclean${reset}    : uv sync --clean
               - pyproject/lock에 없는 패키지를 제거하며 환경을 정리
               - 사실상 uv sync와 동일 (uv sync 기본이 clean 동작)
               - 완전 재설치 원하면: uv sync --reinstall 또는 .venv 삭제 후 uv sync
  ${green}uvcheck${reset}    : uv check
  ${green}uvi${reset}        : install uv tool

${bold}${blue}[Recipes]${reset}

  # 전체 extras 포함 설치
  ${green}uv pip sync --all-extras${reset}

  # 백엔드만
  ${green}uv pip sync --extra backend --extra dev${reset}

  # 프론트엔드만
  ${green}uv pip sync --extra frontend --extra dev${reset}

EOF
}
