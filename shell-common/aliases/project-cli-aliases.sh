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
#   - src/backend/{PYTHON_MODULE}/__main__.py
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

    # Validate src/backend/{module}/__main__.py exists
    local module_path="${python_module//.//}"
    if [ ! -f "src/backend/$module_path/__main__.py" ]; then
        echo "Error: Python module not found: src/backend/$module_path/__main__.py"
        return 1
    fi

    # Remove project_name and python_module from arguments and pass rest to python -m
    shift 2
    PYTHONPATH="src/backend" python -m "$python_module" "$@"
}

# ============================================================================
# JIRAvis CLI
# ============================================================================
# Purpose: Run JIRAvis project CLI tool
# Location: ~/para/project/JIRAvis
# Entry point: src/backend/jira/cli/__main__.py
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
# Confluence CLI (TODO: Implement when project is ready)
# ============================================================================
# Purpose: Run Confluence project CLI tool
# Location: ~/para/project/confluence (TBD)
# Entry point: src/backend/confluence/cli/__main__.py (TBD)
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
# Entry point: src/backend/agent/cli/__main__.py (TBD)
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
