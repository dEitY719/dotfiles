#!/bin/sh
# shell-common/functions/mytool_help.sh
# mytool Help - shared between bash and zsh

mytool_help() {
    ux_header "MyTool - Personal Utility Commands"

    ux_section "Available Commands"
    ux_table_row "srcpack (sp)" "Bundle source code files" "With syntax highlighting"
    ux_table_row "hwinfo" "Display hardware info" "CPU, GPU, memory details"
    ux_table_row "devx stat" "Project statistics" "Commits, tests, files, LOC"
    ux_table_row "agents_init (ai)" "Generate AGENTS.md" "File system for project"
    echo ""

    ux_section "Usage Examples"
    ux_bullet "srcpack --ext .py --max-bytes 50000"
    ux_bullet "sp - Shortcut for 'srcpack --ext .py --max-bytes 33000'"
    ux_bullet "agents_init - Generate AGENTS.md in current directory"
    ux_bullet "ai - Shortcut for 'agents_init'"
    echo ""
}
