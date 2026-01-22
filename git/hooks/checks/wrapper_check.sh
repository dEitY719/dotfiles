#!/usr/bin/env bash

check_wrapper_function() {
    local abs_path="$1"
    local wrapper_violations_file="$2"
    local violations_found=0

    local matches
    matches=$(grep -n "^[a-z_-][a-z0-9_-]*()[[:space:]]*{" "$abs_path" 2>/dev/null || true)

    if [ -n "$matches" ]; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            local line_num
            line_num=$(echo "$line_info" | cut -d: -f1)
            local line_text
            line_text=$(echo "$line_info" | cut -d: -f2-)

            local func_name
            func_name=$(echo "$line_text" | sed 's/^\\s*\\([a-z_-][a-z0-9_-]*\\)().*/\\1/')

            local start_line=$line_num
            local end_line
            end_line=$(awk "NR>$start_line && /^[}]/ {print NR; exit}" "$abs_path")
            [ -z "$end_line" ] && end_line=$((start_line + 5))

            local body
            body=$(sed -n "${start_line},$end_line p" "$abs_path" | \
                sed '1s/.*{\\(.*\\)/\\1/;$s/\\(.*\\)}.*/\\1/' | \
                grep -v '^[[:space:]]*$' | head -1)

            if [[ "$body" =~ ^[[:space:]]*\\$?\\{?[a-z_-][a-z0-9_-]*\\}?[[:space:]]*\"\\$@\"[[:space:]]*$ ]] || \
               [[ "$body" =~ ^[[:space:]]*[a-z_-][a-z0-9_-]*[[:space:]]*\"\\$@\" ]] || \
               [[ "$body" =~ ^[[:space:]]*[a-z_-][a-z0-9_-]*[[:space:]]*$ ]]; then

                local called_func
                called_func=$(echo "$body" | sed 's/.*\\s*\\([a-z_-][a-z0-9_-]*\\).*/\\1/')

                echo "$abs_path:$line_num: [WARNING] Wrapper function anti-pattern: '$func_name() { $called_func ... }'
  This wrapper function only delegates to another function.
  Consider removing the wrapper or using an alias:
    - Option A: alias ${func_name}='${called_func}'
    - Option B: Enhance the wrapper with additional logic
  Reference: git/doc/ANTI_PATTERNS.md" >>"$wrapper_violations_file"
                violations_found=1
            fi
        done <<<"$matches"
    fi

    return $violations_found
}
