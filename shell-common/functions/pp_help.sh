#!/bin/sh
# shell-common/functions/pp_help.sh

_pp_help_summary() {
    ux_info "Usage: pp-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "package: pp_install | pp_install_up | pp_reqs | pp_uninstall | pp_freeze | pp_list | pp_check"
    ux_bullet_sub "quality: code_check | code_fix | code_type"
    ux_bullet_sub "test: test_pytest | test_unittest"
    ux_bullet_sub "docs: docs_gen"
    ux_bullet_sub "details: pp-help <section>  (example: pp-help quality)"
}

_pp_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "package"
    ux_bullet_sub "quality"
    ux_bullet_sub "test"
    ux_bullet_sub "docs"
}

_pp_help_rows_package() {
    ux_table_row "pp_install" "pip install" "Install package"
    ux_table_row "pp_install_up" "upgrade pip & install" "Update pip first"
    ux_table_row "pp_reqs" "pip install -r reqs" "Install from file"
    ux_table_row "pp_uninstall" "pip uninstall -y" "Remove package"
    ux_table_row "pp_freeze" "Freeze to reqs.txt" "Exclude project name"
    ux_table_row "pp_list" "pip list --outdated" "Check updates"
    ux_table_row "pp_check" "pip check" "Verify deps"
}

_pp_help_rows_quality() {
    ux_table_row "code_check" "ruff format & check" "CI mode (check only)"
    ux_table_row "code_fix" "ruff format & fix" "Auto-fix issues"
    ux_table_row "code_type" "mypy ." "Type checking"
}

_pp_help_rows_test() {
    ux_table_row "test_pytest" "pytest -q" "Run pytest (fast)"
    ux_table_row "test_unittest" "unittest discover" "Run unittest"
}

_pp_help_rows_docs() {
    ux_table_row "docs_gen" "sphinx build" "Generate HTML docs"
}

_pp_help_render_section() {
    ux_section "$1"
    "$2"
}

_pp_help_section_rows() {
    case "$1" in
        package|packages|pkg|pip) _pp_help_rows_package ;;
        quality|lint|ruff|mypy) _pp_help_rows_quality ;;
        test|tests|testing) _pp_help_rows_test ;;
        docs|documentation) _pp_help_rows_docs ;;
        *)
            ux_error "Unknown pp-help section: $1"
            ux_info "Try: pp-help --list"
            return 1
            ;;
    esac
}

_pp_help_full() {
    ux_header "Python Package & Quality Tools"
    _pp_help_render_section "Package Management" _pp_help_rows_package
    _pp_help_render_section "Code Quality (Ruff/MyPy)" _pp_help_rows_quality
    _pp_help_render_section "Testing" _pp_help_rows_test
    _pp_help_render_section "Documentation" _pp_help_rows_docs
}

pp_help() {
    case "${1:-}" in
        ""|-h|--help|help) _pp_help_summary ;;
        --list|list|section|sections)        _pp_help_list_sections ;;
        --all|all)          _pp_help_full ;;
        *)                  _pp_help_section_rows "$1" ;;
    esac
}

alias pp-help='pp_help'
