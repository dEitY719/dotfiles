#!/usr/bin/env bash

check_alias_function_conflict() {
    local abs_path="$1"
    local alias_conflict_file="$2"
    local violations_found=0

    local alias_names
    alias_names=$(grep -o "^alias[[:space:]]*[a-z_-][a-z0-9_-]*=" "$abs_path" 2>/dev/null | \
        sed "s/.*alias[[:space:]]*\\([^=]*\\)=.*/\\1/" | sort -u || true)

    local func_names
    func_names=$(grep -o "^[a-z_-][a-z0-9_-]*()[[:space:]]*{" "$abs_path" 2>/dev/null | \
        sed "s/(.*//;s/^[[:space:]]*//;s/[[:space:]]*$//" | sort -u || true)

    if [ -n "$alias_names" ] && [ -n "$func_names" ]; then
        while IFS= read -r alias_name; do
            [ -z "$alias_name" ] && continue
            local normalized_alias="${alias_name//-/_}"

            while IFS= read -r func_name; do
                [ -z "$func_name" ] && continue
                local normalized_func="${func_name//-/_}"

                if [ "$alias_name" = "$func_name" ] || [ "$normalized_alias" = "$normalized_func" ]; then
                    local alias_line
                    alias_line=$(grep -n "^alias[[:space:]]*$alias_name=" "$abs_path" 2>/dev/null | cut -d: -f1 | head -1)
                    local func_line
                    func_line=$(grep -n "^$func_name()[[:space:]]*{" "$abs_path" 2>/dev/null | cut -d: -f1 | head -1)

                    echo "$abs_path:$alias_line,$func_line: [BLOCKING] Alias/function name conflict: '$alias_name'
  The same name exists as both:
    - Alias (line $alias_line): alias $alias_name='...'
    - Function (line $func_line): $func_name() { ... }
  This causes parse errors on reload in zsh.
  Fix: Use different names (e.g., alias 'my-cmd' and function 'my_cmd_impl')
  Reference: git/doc/ANTI_PATTERNS.md" >>"$alias_conflict_file"

                    violations_found=1
                fi
            done <<<"$func_names"
        done <<<"$alias_names"
    fi

    return $violations_found
}
