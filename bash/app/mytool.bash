#!/bin/bash

# 소스 번들링 함수
srcpack() {
    local script="$HOME/dotfiles/mytool/srcpack.py"
    if [ ! -f "$script" ]; then
        echo "not found: $script" >&2
        return 2
    fi
    python "$script" "$@"
}

# 짧은 별칭
alias sp='srcpack --ext .py --max-bytes 33000'
