#!/bin/bash

# =============================================================================
# MyTool - Personal Utility Functions
# =============================================================================

# 도움말 함수
mytool_help() {
    echo ""
    echo "MyTool - Personal Utility Commands"
    echo "===================================="
    echo ""
    echo "Available commands:"
    echo ""
    echo "  ${UX_BOLD}srcpack(sp)${UX_RESET}  - Bundle source code files with syntax highlighting"
    echo "  ${UX_BOLD}hwinfo${UX_RESET}       - Display comprehensive hardware information"
    echo "  ${UX_BOLD}devx stat${UX_RESET}    - Show project statistics (commits, tests, files, LOC)"
    echo ""
    echo "Usage examples:"
    echo "  srcpack --ext .py --max-bytes 50000"
    echo "  sp  # Shortcut for 'srcpack --ext .py --max-bytes 33000'"
    echo "  hwinfo"
    echo "  devx stat"
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

# =============================================================================
# Aliases
# =============================================================================

# 소스 번들링 짧은 별칭
alias sp='srcpack --ext .py --max-bytes 33000'

# 하드웨어 정보 별칭
alias hwinfo='get_hw_info'
