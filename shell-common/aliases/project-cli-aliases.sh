#!/bin/sh
# shell-common/aliases/project-cli-aliases.sh
# Project-specific CLI command aliases
#
# Pattern: Each project with a ./cli script gets:
#   1. A dedicated function: run_PROJECT_cli()
#   2. An alias for convenience: PROJECT-cli
#
# Supported projects:
#   - JIRAvis: jira-cli (calls run_jiravis_cli)
#   - Confluence: confluence-cli (calls run_confluence_cli) [TODO]
#   - Agent: agent-cli (calls run_agent_cli) [TODO]

# ============================================================================
# INTERNAL HELPER: Generic project CLI runner
# ============================================================================
# Usage: _run_project_cli PROJECT_NAME PYTHON_MODULE [cli_args...]
# Example: _run_project_cli "JIRAvis" "jira.cli"
# Example: _run_project_cli "JIRAvis" "jira.cli" "list" "--verbose"
#
# Each project must have:
#   - backend/{PYTHON_MODULE}/__main__.py
#
_run_project_cli() {
    local project_name="$1"
    local python_module="$2"

    if [ -z "$project_name" ] || [ -z "$python_module" ]; then
        echo "Error: _run_project_cli requires project_name and python_module arguments"
        return 1
    fi

    local project_dir="$HOME/para/project/$project_name"

    # Validate project directory exists
    if [ ! -d "$project_dir" ]; then
        echo "Error: Project directory not found: $project_dir"
        return 1
    fi

    # Navigate to project root
    cd "$project_dir" || return 1

    # Validate backend/{module}/__main__.py exists
    local module_path="${python_module//.//}"
    if [ ! -f "backend/$module_path/__main__.py" ]; then
        echo "Error: Python module not found: backend/$module_path/__main__.py"
        return 1
    fi

    # Remove project_name and python_module from arguments and pass rest to python -m
    shift 2
    PYTHONPATH="backend" python -m "$python_module" "$@"
}

# ============================================================================
# JIRAvis CLI
# ============================================================================
# Purpose: Run JIRAvis project CLI tool
# Location: ~/para/project/JIRAvis
# Entry point: backend/jira/cli/__main__.py
#
# Usage:
#   jira-cli                    # Show help/main menu
#   jira-cli list               # Run specific command
#   jira-cli --help             # Show CLI options
#
run_jiravis_cli() {
    _run_project_cli "JIRAvis" "jira.cli" "$@"
}

alias jira-cli='run_jiravis_cli'

# ============================================================================
# JIRAvis Test Runner
# ============================================================================
# Purpose: Run JIRAvis project tests with various options
# Location: ~/para/project/JIRAvis
#
# Usage:
#   jira-test              # Run all tests (recommended)
#   jira-test all          # Run all tests
#   jira-test func         # Run Tool Functions tests (30/30)
#   jira-test api          # Run API Endpoints tests (27/27)
#   jira-test coverage     # Run with coverage report
#   jira-test parallel     # Run tests in parallel
#   jira-test help         # Show help
#
run_jiravis_test() {
    local project_dir="$HOME/para/project/JIRAvis"

    if [ ! -d "$project_dir" ]; then
        echo "Error: Project directory not found: $project_dir"
        return 1
    fi

    cd "$project_dir" || return 1

    case "${1:-all}" in
        all)
            poetry run pytest tests/unit_test/jira/ -v --tb=short "${@:2}"
            ;;
        func)
            poetry run pytest tests/unit_test/jira/issues/test_functions.py -v "${@:2}"
            ;;
        api)
            poetry run pytest tests/unit_test/jira/api/test_issues_router.py -v "${@:2}"
            ;;
        coverage)
            poetry run pytest tests/unit_test/jira/ -v --cov=jira --cov-report=term-missing "${@:2}"
            ;;
        parallel)
            poetry run pytest tests/unit_test/jira/ -v -n auto "${@:2}"
            ;;
        help|--help|-h|'')
            _jiravis_test_help
            ;;
        *)
            ux_error "Unknown option: $1"
            echo ""
            _jiravis_test_help
            return 1
            ;;
    esac
}

_jiravis_test_help() {
    # Load UX library if not already loaded
    if ! declare -f ux_header >/dev/null 2>&1; then
        source "${BASH_SOURCE[0]%/*}/../tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    fi

    ux_header "JIRAvis Test Runner"
    echo ""

    ux_section "Commands"
    ux_bullet "all         Run all tests (default, recommended)"
    ux_bullet "func        Tool Functions tests (30/30 tests)"
    ux_bullet "api         API Endpoints tests (27/27 tests)"
    ux_bullet "coverage    Run all tests with coverage report"
    ux_bullet "parallel    Run all tests in parallel (faster)"
    echo ""

    ux_section "Quick Start"
    ux_numbered "1" "Run all tests (default): jira-test"
    ux_numbered "2" "Test functions only: jira-test func"
    ux_numbered "3" "Test API endpoints: jira-test api"
    echo ""

    ux_section "Advanced Usage"
    ux_bullet "jira-test all -vv              Very verbose output"
    ux_bullet "jira-test func --durations=10  Show slowest tests"
    ux_bullet "jira-test api -k \"create\"     Run only tests matching 'create'"
    ux_bullet "jira-test coverage             Generate coverage report"
    echo ""

    ux_info "Pass additional pytest arguments after the command"
    echo ""
}

alias jira-test='run_jiravis_test'

# ============================================================================
# Confluence CLI (TODO: Implement when project is ready)
# ============================================================================
# Purpose: Run Confluence project CLI tool
# Location: ~/para/project/confluence (TBD)
# Entry point: backend/confluence/cli/__main__.py (TBD)
#
# Usage:
#   confluence-cli              # Show help/main menu
#   confluence-cli sync         # Run specific command
#
# run_confluence_cli() {
#     _run_project_cli "confluence" "confluence.cli" "$@"
# }
#
# alias confluence-cli='run_confluence_cli'

# ============================================================================
# Agent CLI (TODO: Implement when project is ready)
# ============================================================================
# Purpose: Run Agent project CLI tool
# Location: ~/para/project/agent (TBD)
# Entry point: backend/agent/cli/__main__.py (TBD)
#
# Usage:
#   agent-cli                   # Show help/main menu
#   agent-cli train             # Run specific command
#
# run_agent_cli() {
#     _run_project_cli "agent" "agent.cli" "$@"
# }
#
# alias agent-cli='run_agent_cli'
