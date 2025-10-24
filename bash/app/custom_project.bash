#!/usr/bin/env bash
# /bash/app/custom_project.bash
# Shell style: safe defaults

#--------------------------------------
# Project Roots & Common
#--------------------------------------
# (참고) 프로젝트 루트에서 실행 가정. 필요 시 git 기반 루트 감지:
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

#--------------------------------------
# Repos (문서/헬프에만 표기)
#--------------------------------------
REPO_DOTFILES_URL="https://github.com/dEitY719/dotfiles.git"
REPO_FINRX_URL="https://github.com/dEitY719/FinRx.git"
REPO_DMC_PG_URL="https://github.com/dEitY719/dmc-playground.git"

#--------------------------------------
# Ports / Hosts (요구사항 1)
#  - 여기만 고치면 alias/clihelp 전역 반영 (요구사항 2)
#--------------------------------------
DEV_HOST="127.0.0.1"
TEST_HOST="127.0.0.1"
PROD_HOST="0.0.0.0"

DEV_PORT=8000
TEST_PORT=8001
PROD_PORT=8719

# smithery-playground 전용 포트
SMT_DEV_PORT=9001
SMT_TEST_PORT=9002
SMT_PROD_PORT=9019

# Derived API URLs (dmc-playground)
DEV_API_URL="http://${DEV_HOST}:${DEV_PORT}"
TEST_API_URL="http://${TEST_HOST}:${TEST_PORT}"
PROD_API_URL="http://${PROD_HOST}:${PROD_PORT}"

# smithery-playground 서비스 URL
SMT_DEV_URL="http://${DEV_HOST}:${SMT_DEV_PORT}"
SMT_TEST_URL="http://${TEST_HOST}:${SMT_TEST_PORT}"
SMT_PROD_URL="http://${PROD_HOST}:${SMT_PROD_PORT}"

#--------------------------------------
# Database URLs (기존 값 변수화 & 재사용)
#--------------------------------------
DB_USER="dmc_user"
DB_PASS="change_me_strong_pw"
DB_HOST="localhost"
DB_PORT="5432"

DB_NAME_DEV="dmc_playground_dev"
DB_NAME_TEST="dmc_playground_test"
DB_NAME_PROD="dmc_playground_prod"

DEV_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_DEV}"
TEST_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_TEST}"
PROD_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_PROD}"

#--------------------------------------
# Small helpers
#--------------------------------------
_have() { command -v "$1" >/dev/null 2>&1; }

_need() {
    if ! _have "$1"; then
        echo "[ERR] '$1' 명령을 찾을 수 없습니다. 설치 후 다시 시도하세요." >&2
        return 127
    fi
}

#--------------------------------------
# FinRx
#--------------------------------------
run_fr_cli() {
    _need python
    python ./src/ticker_library/cli/cli.py "$@"
}

#--------------------------------------
# dmc-playground (FastAPI + Uvicorn)
#  - dev/test는 --reload 유지, prod는 --reload 제거 (원문 주석 반영)
#--------------------------------------
run_bes() {
    _need uv
    uv run uvicorn src.backend.main:app \
        --reload \
        --host "${DEV_HOST}" --port "${DEV_PORT}"
}

run_tbes() {
    _need uv
    PYTEST_CURRENT_TEST=1 uv run uvicorn src.backend.main:app \
        --reload \
        --host "${TEST_HOST}" --port "${TEST_PORT}"
}

run_pbes() {
    _need uvicorn
    APP_ENV=production uvicorn src.backend.main:app \
        --host "${PROD_HOST}" --port "${PROD_PORT}"
}

#--------------------------------------
# API / DB CLIs
#  - 인자 미지정 시 환경별 기본 URL 사용
#  - 인자 지정 시 해당 값으로 덮어씌움
#--------------------------------------
run_api_cli() {
    _need python
    local url="${1:-${DEV_API_URL}}"
    python src/backend/api_cli.py "${url}"
}

run_tapi_cli() {
    _need python
    local url="${1:-${TEST_API_URL}}"
    python src/backend/api_cli.py "${url}"
}

run_papi_cli() {
    _need python
    local url="${1:-${PROD_API_URL}}"
    python src/backend/api_cli.py "${url}"
}

run_db_cli() {
    _need python
    local url="${1:-${DEV_DB_URL}}"
    python src/database/db_cli.py "${url}"
}

run_tdb_cli() {
    _need python
    local url="${1:-${TEST_DB_URL}}"
    python src/database/db_cli.py "${url}"
}

run_pdb_cli() {
    _need python
    local url="${1:-${PROD_DB_URL}}"
    python src/database/db_cli.py "${url}"
}

#--------------------------------------
# smithery-playground (FastAPI + Uvicorn)
#  - dmc와 동일한 패턴: dev/test는 --reload, prod는 no reload
#--------------------------------------
run_smt() {
    _need uv
    uv run uvicorn src.main:app \
        --reload \
        --host "${DEV_HOST}" --port "${SMT_DEV_PORT}"
}

run_tsmt() {
    _need uv
    PYTEST_CURRENT_TEST=1 uv run uvicorn src.main:app \
        --reload \
        --host "${TEST_HOST}" --port "${SMT_TEST_PORT}"
}

run_psmt() {
    _need uvicorn
    APP_ENV=production uvicorn src.main:app \
        --host "${PROD_HOST}" --port "${SMT_PROD_PORT}"
}

#--------------------------------------
# Help (요구사항 2: 변수 자동 반영)
#--------------------------------------
clihelp() {
    cat <<-EOF

[Custom Project CLI Help]

Repos
  • dotfiles         ✨ ${REPO_DOTFILES_URL}
  • FinRx            💰 ${REPO_FINRX_URL}
  • dmc-playground   📚 ${REPO_DMC_PG_URL}

Hosts / Ports
  - DEV  : ${DEV_HOST}:${DEV_PORT}  (SMT ${SMT_DEV_PORT})
  - TEST : ${TEST_HOST}:${TEST_PORT} (SMT ${SMT_TEST_PORT})
  - PROD : ${PROD_HOST}:${PROD_PORT} (SMT ${SMT_PROD_PORT})

Service URLs (smithery-playground)
  - DEV  : ${SMT_DEV_URL}
  - TEST : ${SMT_TEST_URL}
  - PROD : ${SMT_PROD_URL}

API URLs (dmc-playground, 기본값)
  - DEV  : ${DEV_API_URL}
  - TEST : ${TEST_API_URL}
  - PROD : ${PROD_API_URL}

DB URLs (dmc-playground, 기본값)
  - DEV  : ${DEV_DB_URL}
  - TEST : ${TEST_DB_URL}
  - PROD : ${PROD_DB_URL}

Aliases / Commands

  [FinRx]
    run_fr_cli                 : python ./src/ticker_library/cli/cli.py

  [dmc-playground]
    run_bes                    : uv run uvicorn src.backend.main:app --reload --host ${DEV_HOST} --port ${DEV_PORT}
    run_tbes                   : PYTEST_CURRENT_TEST=1 uv run uvicorn src.backend.main:app --reload --host ${TEST_HOST} --port ${TEST_PORT}
    run_pbes                   : APP_ENV=production uvicorn src.backend.main:app --host ${PROD_HOST} --port ${PROD_PORT}

    run_api_cli [API_URL?]     : 기본 ${DEV_API_URL}
    run_tapi_cli [API_URL?]    : 기본 ${TEST_API_URL}
    run_papi_cli [API_URL?]    : 기본 ${PROD_API_URL}

    run_db_cli  [DB_URL?]      : 기본 ${DEV_DB_URL}
    run_tdb_cli [DB_URL?]      : 기본 ${TEST_DB_URL}
    run_pdb_cli [DB_URL?]      : 기본 ${PROD_DB_URL}

  [smithery-playground]
    run_smt                    : uv run uvicorn src.main:app --reload --host ${DEV_HOST}  --port ${SMT_DEV_PORT}
    run_tsmt                   : PYTEST_CURRENT_TEST=1 uv run uvicorn src.main:app --reload --host ${TEST_HOST} --port ${SMT_TEST_PORT}
    run_psmt                   : APP_ENV=production uvicorn src.main:app --host ${PROD_HOST} --port ${SMT_PROD_PORT}

Recipes

  # 백엔드 개발 서버 실행 (FastAPI + Uvicorn, hot reload)
  run_bes

  # 테스트 서버 실행 (hot reload)
  run_tbes

  # 프로덕션 서버 실행 (no reload)
  run_pbes

  # API 유틸리티 CLI 사용 (기본 DEV URL)
  run_api_cli --help
  run_api_cli               # -> ${DEV_API_URL}
  run_tapi_cli              # -> ${TEST_API_URL}
  run_papi_cli              # -> ${PROD_API_URL}

  # DB 유틸리티 CLI 사용 (기본 DEV DB URL)
  run_db_cli --help
  run_db_cli                # -> ${DEV_DB_URL}
  run_tdb_cli               # -> ${TEST_DB_URL}
  run_pdb_cli               # -> ${PROD_DB_URL}

  # smithery-playground 서버 실행
  run_smt                   # -> ${SMT_DEV_URL} (reload)
  run_tsmt                  # -> ${SMT_TEST_URL} (reload)
  run_psmt                  # -> ${SMT_PROD_URL} (no reload)

Tips
  - 가능한 프로젝트 루트에서 실행하세요. (현재: ${PROJECT_ROOT})
  - 가상환경은 uv/pyproject 기반 권장 (예: uvs / uvd)
  - 프로덕션에서는 --reload 옵션을 사용하지 않습니다.

EOF
}

# 끝.
