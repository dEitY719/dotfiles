#!/bin/sh
# shell-common/projects/smithery.sh
# smithery-playground project utilities (FastAPI service)
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Hosts & Ports Configuration
# ═══════════════════════════════════════════════════════════════

# Development, Test, Production hosts
DEV_HOST="127.0.0.1"
TEST_HOST="127.0.0.1"
PROD_HOST="0.0.0.0"

# smithery-playground ports
SMT_DEV_PORT=9001
SMT_TEST_PORT=9002
SMT_PROD_PORT=9019

# ═══════════════════════════════════════════════════════════════
# Service URLs (derived from host/port)
# ═══════════════════════════════════════════════════════════════

SMT_DEV_URL="http://${DEV_HOST}:${SMT_DEV_PORT}"
SMT_TEST_URL="http://${TEST_HOST}:${SMT_TEST_PORT}"
SMT_PROD_URL="http://${PROD_HOST}:${SMT_PROD_PORT}"

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
