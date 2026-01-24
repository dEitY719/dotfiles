#!/usr/bin/env bash

check_function_naming() {
    local abs_path="$1"
    local func_violations_file="$2"
    local violations_found=0

    while IFS= read -r line_info; do
        [ -z "$line_info" ] && continue
        local line_num
        line_num=$(echo "$line_info" | cut -d: -f1)
        local line_text
        line_text=$(echo "$line_info" | cut -d: -f2-)

        local func_name="${line_text##*( )}"
        func_name="${func_name%%\(\)*}"

        if [[ "$func_name" == *"-"* ]]; then
            local corrected="${func_name//-/_}"
            echo "$abs_path:$line_num: Function '$func_name' uses dash-form. Use snake_case: '$corrected'" >>"$func_violations_file"
            violations_found=1
        fi
    done < <(grep -n "[a-z0-9_]*-[a-z0-9_]*()[[:space:]]*{" "$abs_path" 2>/dev/null || true)

    return $violations_found
}
check_naming_violations() {
    local abs_path="$1"
    local violations_file="$2"

    local filename
    filename=$(basename "$abs_path" .sh)

    local violations_found=0

    [[ "$filename" != *_* ]] && return 0

    while IFS= read -r func_name; do
        [[ -z "$func_name" ]] && continue
        local matches
        matches=$(
            grep -n "\".*$func_name.*\"" "$abs_path" 2>/dev/null | \
                grep -v ":[[:space:]]*#" | \
                grep -v "alias.*=" | \
                grep -v ":[[:space:]]*$func_name()" || true
        )

        if [ -n "$matches" ]; then
            printf '%s\n' "$matches" | sed "s|^|$abs_path:|" >>"$violations_file" 2>/dev/null
            violations_found=1
        fi
    done < <(grep "^[[:space:]]*[a-z_][a-z0-9_]*()[[:space:]]*{" "$abs_path" | \
        sed 's/^[[:space:]]*\([a-z_][a-z0-9_]*\)().*/\1/')

    return $violations_found
}
