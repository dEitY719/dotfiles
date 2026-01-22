#!/usr/bin/env bash

check_ux_library_usage() {
    local abs_path="$1"

    grep -q "ux_header\|ux_error\|ux_success" "$abs_path" || return 0

    if grep -q "if.*\\(type\\|command -v\\).*ux_[a-z_]*.*>/dev/null" "$abs_path"; then
        return 0
    fi

    local violation_count=0
    while IFS= read -r line_text; do
        # Ignore comments (defensive; grep source already excludes simple comment lines)
        [[ "$line_text" == [[:space:]]#* ]] && continue

        # Ignore empty/whitespace-only echoes
        [[ "$line_text" =~ ^[[:space:]]*echo[[:space:]]*\"\"[[:space:]]*$ ]] && continue
        [[ "$line_text" =~ ^[[:space:]]*echo[[:space:]]*\'\'[[:space:]]*$ ]] && continue
        [[ "$line_text" =~ ^[[:space:]]*echo[[:space:]]*\"[[:space:]]*\"[[:space:]]*$ ]] && continue

        # Ignore echos that are part of pipelines or command substitutions
        [[ "$line_text" == *"|"* ]] && continue
        [[ "$line_text" == *'$('* ]] && continue

        if [[ "$line_text" =~ [[:space:]]echo[[:space:]]+.*[[:alnum:]] ]]; then
            ((violation_count++))
        fi
    done < <(grep "^[^#]*echo[[:space:]]" "$abs_path" | grep -v "ux_" | grep -v "() {" || true)

    [ $violation_count -eq 0 ] && return 0
    return 1
}
