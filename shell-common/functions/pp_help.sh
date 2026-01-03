#!/bin/sh
# shell-common/functions/pp_help.sh
# ppHelp - shared between bash and zsh

pp_help() {
    ux_header "Python Package & Quality Tools"

    ux_section "Package Management"
    ux_table_row "pp_install" "pip install" "Install package"
    ux_table_row "pp_install_up" "upgrade pip & install" "Update pip first"
    ux_table_row "pp_reqs" "pip install -r reqs" "Install from file"
    ux_table_row "pp_uninstall" "pip uninstall -y" "Remove package"
    ux_table_row "pp_freeze" "Freeze to reqs.txt" "Exclude project name"
    ux_table_row "pp_list" "pip list --outdated" "Check updates"
    ux_table_row "pp_check" "pip check" "Verify deps"
    echo ""

    ux_section "Code Quality (Ruff/MyPy)"
    ux_table_row "code_check" "ruff format & check" "CI mode (check only)"
    ux_table_row "code_fix" "ruff format & fix" "Auto-fix issues"
    ux_table_row "code_type" "mypy ." "Type checking"
    echo ""

    ux_section "Testing"
    ux_table_row "test_pytest" "pytest -q" "Run pytest (fast)"
    ux_table_row "test_unittest" "unittest discover" "Run unittest"
    echo ""

    ux_section "Documentation"
    ux_table_row "docs_gen" "sphinx build" "Generate HTML docs"
    echo ""
}

# Alias for pp-help format (using dash instead of underscore)
alias pp-help='pp_help'
