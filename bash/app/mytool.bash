#!/bin/bash

# =============================================================================
# MyTool - Personal Utility Functions
# =============================================================================

# 도움말 함수

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
