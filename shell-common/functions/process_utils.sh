#!/bin/sh
# shell-common/functions/process_utils.sh
# Process management utilities

psgrep() {
    local pattern="$1"

    if [ -z "$pattern" ]; then
        echo "Usage: ps-grep <pattern>"
        echo "Example: ps-grep claude"
        return 1
    fi

    ps aux | grep "$pattern" | grep -v grep
}
