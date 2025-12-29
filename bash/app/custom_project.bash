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

# 끝.
