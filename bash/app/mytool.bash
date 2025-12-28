#!/bin/bash

# =============================================================================
# MyTool - Personal Utility Functions
# =============================================================================

# 도움말 함수
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

# 하드웨어 정보 표시 함수
get_hw_info() {
    local script="$HOME/dotfiles/mytool/get_hw_info.sh"
    if [ ! -f "$script" ]; then
        echo "Error: Hardware info script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# 소스 번들링 함수
srcpack() {
    local script="$HOME/dotfiles/mytool/srcpack.py"
    if [ ! -f "$script" ]; then
        echo "not found: $script" >&2
        return 2
    fi
    python "$script" "$@"
}

# AGENTS.md 생성 함수
agents_init() {
    local script="$HOME/dotfiles/mytool/run-AGENTS_md_Master_Prompt.sh"
    if [ ! -f "$script" ]; then
        echo "Error: AGENTS.md generation script not found: $script" >&2
        return 2
    fi
    bash "$script" "$@"
}

# =============================================================================
# Aliases
# =============================================================================

# MyTool 도움말 별칭
alias mthelp='mytool_help'

# 소스 번들링 짧은 별칭
alias sp='srcpack --ext .py --max-bytes 33000'

# 하드웨어 정보 별칭
alias hwinfo='get_hw_info'

# AGENTS.md 생성 짧은 별칭
alias ai='agents_init'
