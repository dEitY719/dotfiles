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
alias uvs='uv sync'                                  # 기본/프로덕션 동기화
alias uvu='uv sync --upgrade'                        # 업그레이드 동기화
alias uvd='uv sync --dev --extra dev'                # dev 환경 설치
alias uvp='uv sync'                                  # prod 동기화(=uvs)
alias uvl='uv lock'                                  # lock 파일 갱신

# (3) export / requirements 기반 sync
alias uvc='uv pip compile pyproject.toml -o requirements.txt'
alias uvr='uv pip sync requirements.txt'

# (4) 클린 동기화 (여분 패키지 제거, 기본 동작과 동일)
alias uvclean='uv sync --clean'

# (5) 상태/검증
alias uv_check='uv pip check'

# (6) 도움말(프로젝트 관례 안내)
uvh() {
  cat <<-'EOF'

[UV Quick Commands]

  uvs        : uv sync (base/prod)
  uvu        : uv sync --upgrade (업그레이드 동기화)
  uvd        : uv sync --dev --extra dev
  uvp        : uv sync (prod)
  uvl        : uv lock
  uvc        : uv pip compile pyproject.toml -o requirements.txt
  uvr        : uv pip sync requirements.txt
  uvclean    : uv sync --clean
               - pyproject/lock에 없는 패키지를 제거하며 환경을 정리
               - 사실상 uv sync와 동일 (uv sync 기본이 clean 동작)
               - 완전 재설치 원하면: uv sync --reinstall 또는 .venv 삭제 후 uv sync
  uv_check   : uv check
  uvi        : install uv tool

[Recipes]

  # 전체 extras 포함 설치
  uv pip sync --all-extras

  # 백엔드만
  uv pip sync --extra backend --extra dev

  # 프론트엔드만
  uv pip sync --extra frontend --extra dev

EOF
}
