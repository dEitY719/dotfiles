#!/usr/bin/env bash

check_subshell_sourcing() {
    local abs_path="$1"
    local subshell_violations_file="$2"

    local matches
    matches=$(grep -n '[a-z_][a-z0-9_]*\\s*=\\s*\\$(' "$abs_path" 2>/dev/null | grep -E '\\.(sh|zsh|bash)\\s*\\)' || true)

    if [ -n "$matches" ]; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            local line_num
            line_num=$(echo "$line_info" | cut -d: -f1)
            local line_text
            line_text=$(echo "$line_info" | cut -d: -f2-)

            local var_name
            var_name=$(echo "$line_text" | sed 's/.*\\([a-z_][a-z0-9_]*\\)\\s*=\\s*\\$(.*/\\1/')

            echo "$abs_path:$line_num: [WARNING] Subshell sourcing breaks function propagation: '${var_name}=\$(...)'
  Fix: Use direct sourcing '. file' instead of '\${var_name}=\$(. file)'
  Reference: git/doc/ANTI_PATTERNS.md" >>"$subshell_violations_file"
        done <<<"$matches"
        return 1
    fi

    return 0
}
