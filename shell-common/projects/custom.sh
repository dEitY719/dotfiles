#!/bin/sh
# shell-common/projects/custom.sh
# Custom project utilities - FinRx, dmc-playground, smithery-playground
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Project Roots & Common Configuration
# ═══════════════════════════════════════════════════════════════

# Detect project root from git (assumes execution from project directory)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ═══════════════════════════════════════════════════════════════
# Repository URLs (for documentation & reference)
# ═══════════════════════════════════════════════════════════════

REPO_DOTFILES_URL="https://github.com/dEitY719/dotfiles.git"
REPO_FINRX_URL="https://github.com/dEitY719/FinRx.git"
REPO_DMC_PG_URL="https://github.com/dEitY719/dmc-playground.git"

# ═══════════════════════════════════════════════════════════════
# Hosts & Ports Configuration
# ═══════════════════════════════════════════════════════════════

# Development, Test, Production hosts
DEV_HOST="127.0.0.1"
TEST_HOST="127.0.0.1"
PROD_HOST="0.0.0.0"

# dmc-playground ports
DEV_PORT=8000
TEST_PORT=8001
PROD_PORT=8719

# smithery-playground ports
SMT_DEV_PORT=9001
SMT_TEST_PORT=9002
SMT_PROD_PORT=9019

# ═══════════════════════════════════════════════════════════════
# API Service URLs (derived from host/port)
# ═══════════════════════════════════════════════════════════════

# dmc-playground API URLs
DEV_API_URL="http://${DEV_HOST}:${DEV_PORT}"
TEST_API_URL="http://${TEST_HOST}:${TEST_PORT}"
PROD_API_URL="http://${PROD_HOST}:${PROD_PORT}"

# smithery-playground service URLs
SMT_DEV_URL="http://${DEV_HOST}:${SMT_DEV_PORT}"
SMT_TEST_URL="http://${TEST_HOST}:${SMT_TEST_PORT}"
SMT_PROD_URL="http://${PROD_HOST}:${SMT_PROD_PORT}"

# ═══════════════════════════════════════════════════════════════
# Database Configuration
# ═══════════════════════════════════════════════════════════════

DB_USER="dmc_user"
DB_PASS="change_me_strong_pw"
DB_HOST="localhost"
DB_PORT="5432"

# Database names
DB_NAME_DEV="dmc_playground_dev"
DB_NAME_TEST="dmc_playground_test"
DB_NAME_PROD="dmc_playground_prod"

# Database URLs
DEV_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_DEV}"
TEST_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_TEST}"
PROD_DB_URL="postgresql+asyncpg://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME_PROD}"

# ═══════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════

# Check if command exists
_have() {
    command -v "$1" > /dev/null 2>&1
}

# Require a command or exit with error
_need() {
    if ! _have "$1"; then
        echo "[ERR] Cannot find command '$1'. Please install it and try again." >&2
        return 127
    fi
}

# ═══════════════════════════════════════════════════════════════
# FinRx Project Functions
# ═══════════════════════════════════════════════════════════════

run_fr_cli() {
    _need python
    python ./src/ticker_library/cli/cli.py "$@"
}

# ═══════════════════════════════════════════════════════════════
# dmc-playground Backend Functions (FastAPI + Uvicorn)
# Dev/Test: with --reload flag
# Prod: without --reload flag
# ═══════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════
# dmc-playground API & Database CLI Functions
# Arguments: [optional url] - uses environment-specific default if not provided
# ═══════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════
# smithery-playground Backend Functions (FastAPI + Uvicorn)
# Dev/Test: with --reload flag
# Prod: without --reload flag
# ═══════════════════════════════════════════════════════════════

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
