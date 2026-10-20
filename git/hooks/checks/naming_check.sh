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
        # Skip short function names (<=3 chars) — too many false positives in help text
        [[ ${#func_name} -le 3 ]] && continue
        # A line that starts with `"${SHELL_COMMON...}"/tools/custom/` runs that
        # executable (the #2195 one-line wrapper, #2255); it is a command, not
        # user-facing text, whichever function name the path contains. A
        # message that merely mentions the path (`"... see tools/custom/x.sh"`)
        # does not start that way and stays flagged.
        local matches
        matches=$(
            grep -n "\".*$func_name.*\"" "$abs_path" 2>/dev/null |
                grep -v ":[[:space:]]*#" |
                grep -v "alias.*=" |
                grep -v ":[[:space:]]*$func_name()" |
                grep -v '^[0-9][0-9]*:[[:space:]]*"${SHELL_COMMON[^"]*"/tools/custom/' |
                grep -v "ux_info\|ux_header\|ux_error\|ux_success\|ux_warning\|ux_bullet\|ux_table_row" || true
        )

        if [ -n "$matches" ]; then
            printf '%s\n' "$matches" | sed "s|^|$abs_path:|" >>"$violations_file" 2>/dev/null
            violations_found=1
        fi
    done < <(grep "^[[:space:]]*[a-z_][a-z0-9_]*()[[:space:]]*{" "$abs_path" |
        sed 's/^[[:space:]]*\([a-z_][a-z0-9_]*\)().*/\1/')

    return $violations_found
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
# per-shell-file: the runner only passes shell-common/functions/*.sh and
# shell-common/tools/integrations/*.sh paths that exist in the worktree.
CHECK_NAME=naming
CHECK_SCOPE=per-shell-file
CHECK_SEVERITY=blocking
CHECK_TITLE="Naming convention violations"
CHECK_REPORT_LINES=10
CHECK_HINT="User-facing text must use dash-form; function definitions must use snake_case."
check_run() {
    local abs_path="$1/$3" out="$4" rc=0
    case "$3" in shell-common/functions/*.sh) ;; *) return 0 ;; esac
    check_naming_violations "$abs_path" "$out" 2>/dev/null || rc=1
    check_function_naming "$abs_path" "$out" 2>/dev/null || rc=1
    return "$rc"
}
