#!/bin/sh
# shell-common/functions/cli_help.sh

cli_help() {
    ux_header "Custom Project CLI Help"

    ux_section "Repositories"
    ux_table_row "dotfiles" "✨" "${REPO_DOTFILES_URL}"
    ux_table_row "FinRx" "💰" "${REPO_FINRX_URL}"
    ux_table_row "dmc-playground" "📚" "${REPO_DMC_PG_URL}"

    ux_section "Service URLs"
    ux_table_row "DEV" "${SMT_DEV_URL} (port ${SMT_DEV_PORT})" "smithery-playground"
    ux_table_row "TEST" "${SMT_TEST_URL} (port ${SMT_TEST_PORT})" "smithery-playground"
    ux_table_row "PROD" "${SMT_PROD_URL} (port ${SMT_PROD_PORT})" "smithery-playground"

    ux_section "FinRx Commands"
    ux_table_row "run_fr_cli" "python ./src/ticker_library/cli/cli.py" "Run CLI"

    ux_section "dmc-playground Commands"
    ux_table_row "run_bes" "Backend dev server (reload)" "DEV: ${DEV_API_URL}"
    ux_table_row "run_tbes" "Backend test server (reload)" "TEST: ${TEST_API_URL}"
    ux_table_row "run_pbes" "Backend prod server (no reload)" "PROD: ${PROD_API_URL}"
    ux_table_row "run_api_cli [URL]" "API CLI (default: DEV)" "Query/test API"
    ux_table_row "run_db_cli [URL]" "DB CLI (default: DEV)" "Query/test database"

    ux_section "smithery-playground Commands"
    ux_table_row "run_smt" "Dev server (reload)" "URL: ${SMT_DEV_URL}"
    ux_table_row "run_tsmt" "Test server (reload)" "URL: ${SMT_TEST_URL}"
    ux_table_row "run_psmt" "Prod server (no reload)" "URL: ${SMT_PROD_URL}"

    ux_section "Tips"
    ux_bullet "Run from project root (current: ${PROJECT_ROOT})"
    ux_bullet "Recommend uv/pyproject-based venv (uvs/uvd)"
    ux_bullet "Never use --reload in production"
}

alias cli-help='cli_help'
