#!/bin/sh
# shell-common/functions/cli_help.sh

_cli_help_summary() {
    ux_info "Usage: cli-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "repos: dotfiles | FinRx | dmc-playground"
    ux_bullet_sub "urls: DEV | TEST | PROD"
    ux_bullet_sub "finrx: run_fr_cli"
    ux_bullet_sub "dmc: run_bes | run_tbes | run_pbes | run_api_cli | run_db_cli"
    ux_bullet_sub "smt: run_smt | run_tsmt | run_psmt"
    ux_bullet_sub "tips: project root | uv venv | no --reload in prod"
    ux_bullet_sub "details: cli-help <section>  (example: cli-help repos)"
}

_cli_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "repos"
    ux_bullet_sub "urls"
    ux_bullet_sub "finrx"
    ux_bullet_sub "dmc"
    ux_bullet_sub "smt"
    ux_bullet_sub "tips"
}

_cli_help_rows_repos() {
    ux_table_row "dotfiles" "✨" "${REPO_DOTFILES_URL}"
    ux_table_row "FinRx" "💰" "${REPO_FINRX_URL}"
    ux_table_row "dmc-playground" "📚" "${REPO_DMC_PG_URL}"
}

_cli_help_rows_urls() {
    ux_table_row "DEV" "${SMT_DEV_URL} (port ${SMT_DEV_PORT})" "smithery-playground"
    ux_table_row "TEST" "${SMT_TEST_URL} (port ${SMT_TEST_PORT})" "smithery-playground"
    ux_table_row "PROD" "${SMT_PROD_URL} (port ${SMT_PROD_PORT})" "smithery-playground"
}

_cli_help_rows_finrx() {
    ux_table_row "run_fr_cli" "python ./src/ticker_library/cli/cli.py" "Run CLI"
}

_cli_help_rows_dmc() {
    ux_table_row "run_bes" "Backend dev server (reload)" "DEV: ${DEV_API_URL}"
    ux_table_row "run_tbes" "Backend test server (reload)" "TEST: ${TEST_API_URL}"
    ux_table_row "run_pbes" "Backend prod server (no reload)" "PROD: ${PROD_API_URL}"
    ux_table_row "run_api_cli [URL]" "API CLI (default: DEV)" "Query/test API"
    ux_table_row "run_db_cli [URL]" "DB CLI (default: DEV)" "Query/test database"
}

_cli_help_rows_smt() {
    ux_table_row "run_smt" "Dev server (reload)" "URL: ${SMT_DEV_URL}"
    ux_table_row "run_tsmt" "Test server (reload)" "URL: ${SMT_TEST_URL}"
    ux_table_row "run_psmt" "Prod server (no reload)" "URL: ${SMT_PROD_URL}"
}

_cli_help_rows_tips() {
    ux_bullet "Run from project root (current: ${PROJECT_ROOT})"
    ux_bullet "Recommend uv/pyproject-based venv (uvs/uvd)"
    ux_bullet "Never use --reload in production"
}

_cli_help_render_section() {
    ux_section "$1"
    "$2"
}

_cli_help_section_rows() {
    case "$1" in
        repos|repositories) _cli_help_rows_repos ;;
        urls|services)      _cli_help_rows_urls ;;
        finrx)              _cli_help_rows_finrx ;;
        dmc|dmc-playground) _cli_help_rows_dmc ;;
        smt|smithery|smithery-playground) _cli_help_rows_smt ;;
        tips)               _cli_help_rows_tips ;;
        *)
            ux_error "Unknown cli-help section: $1"
            ux_info "Try: cli-help --list"
            return 1
            ;;
    esac
}

_cli_help_full() {
    ux_header "Custom Project CLI Help"
    _cli_help_render_section "Repositories" _cli_help_rows_repos
    _cli_help_render_section "Service URLs" _cli_help_rows_urls
    _cli_help_render_section "FinRx Commands" _cli_help_rows_finrx
    _cli_help_render_section "dmc-playground Commands" _cli_help_rows_dmc
    _cli_help_render_section "smithery-playground Commands" _cli_help_rows_smt
    _cli_help_render_section "Tips" _cli_help_rows_tips
}

cli_help() {
    case "${1:-}" in
        ""|-h|--help|help) _cli_help_summary ;;
        --list|list|section|sections)        _cli_help_list_sections ;;
        --all|all)          _cli_help_full ;;
        *)                  _cli_help_section_rows "$1" ;;
    esac
}

alias cli-help='cli_help'
