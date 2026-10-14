#!/usr/bin/env bash

check_subshell_sourcing() {
    local abs_path="$1"
    local subshell_violations_file="$2"

    local matches
    matches=$(grep -n '[a-z_][a-z0-9_]*[[:space:]]*=[[:space:]]*\$(' "$abs_path" 2>/dev/null | grep -E '\.(sh|zsh|bash)[[:space:]]*\)' || true)

    if [ -n "$matches" ]; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            local line_num
            line_num=$(echo "$line_info" | cut -d: -f1)
            local line_text
            line_text=$(echo "$line_info" | cut -d: -f2-)

            local var_name
            var_name=$(echo "$line_text" | sed 's/.*\([a-z_][a-z0-9_]*\)[[:space:]]*=[[:space:]]*\$(.*/\1/')

            echo "$abs_path:$line_num: [WARNING] Subshell sourcing breaks function propagation: '${var_name}=\$(...)'
  Fix: Use direct sourcing '. file' instead of '\${var_name}=\$(. file)'
  Reference: git/doc/ANTI_PATTERNS.md" >>"$subshell_violations_file"
        done <<<"$matches"
        return 1
    fi

    return 0
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
# per-shell-file: the runner only passes shell-common/functions/*.sh and
# shell-common/tools/integrations/*.sh paths that exist in the worktree.
CHECK_NAME=subshell_sourcing
CHECK_SCOPE=per-shell-file
CHECK_SEVERITY=warning
CHECK_TITLE="Subshell sourcing anti-pattern"
CHECK_REPORT_LINES=3
check_run() { check_subshell_sourcing "$1/$3" "$4" 2>/dev/null; }
