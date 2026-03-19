#!/bin/sh
# shell-common/functions/file_cleanup.sh
# Interactive cleanup for backup/original files in the current directory

_cleanup_set_default_patterns() {
    CLEANUP_DEFAULT_PATTERNS=(
        '.*backup*'
        '.*.bak*'
        '.*-original'
    )
}

_cleanup_collect_matches() {
    local search_dir="$1"
    shift

    local find_args=("$search_dir" -maxdepth 1 -type f "(")
    local first_pattern=1
    local pattern=""

    for pattern in "$@"; do
        if [ "$first_pattern" -eq 0 ]; then
            find_args+=(-o)
        fi
        find_args+=(-name "$pattern")
        first_pattern=0
    done
    find_args+=(")")

    CLEANUP_MATCHES_OUTPUT="$(find "${find_args[@]}" -print 2>/dev/null | LC_ALL=C sort -u)"
}

_cleanup_file_size() {
    local file="$1"
    CLEANUP_FILE_SIZE="$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || printf '%s\n' '?')"
}

_cleanup_preview() {
    local search_dir="$1"
    shift

    local patterns=("$@")
    local files=()
    local matches=""
    local file=""

    _cleanup_collect_matches "$search_dir" "${patterns[@]}"
    matches="$CLEANUP_MATCHES_OUTPUT"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        files+=("$file")
    done <<EOF
$matches
EOF

    ux_header "File Cleanup Preview"
    ux_section "Target Directory"
    ux_bullet "$search_dir"

    ux_section "Patterns"
    for file in "${patterns[@]}"; do
        ux_bullet "$file"
    done

    if [ "${#files[@]}" -eq 0 ]; then
        ux_warning "No matching files found"
        return 1
    fi

    ux_section "Matched Files (${#files[@]})"
    for file in "${files[@]}"; do
        local size=""
        _cleanup_file_size "$file"
        size="$CLEANUP_FILE_SIZE"
        ux_bullet "$(basename "$file") ($size bytes)"
    done

    DEL_FILE_MATCHED_FILES=("${files[@]}")
    return 0
}

_cleanup_delete_one() {
    local file="$1"
    if rm -f -- "$file" 2>/dev/null; then
        ux_success "Deleted: $file"
        return 0
    fi

    ux_error "Failed to delete: $file"
    return 1
}

_cleanup_delete_all() {
    local files=("$@")
    local file=""
    local success_count=0
    local error_count=0

    if ! ux_confirm "Delete all ${#files[@]} file(s)?" "n"; then
        ux_info "Operation cancelled"
        return 0
    fi

    ux_section "Deleting Files"
    for file in "${files[@]}"; do
        if _cleanup_delete_one "$file"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
    done

    ux_section "Summary"
    if [ "$error_count" -eq 0 ]; then
        ux_success "$success_count file(s) deleted successfully"
        return 0
    fi

    ux_warning "$success_count succeeded, $error_count failed"
    return 1
}

_cleanup_delete_individually() {
    local files=("$@")
    local file=""
    local success_count=0
    local skip_count=0
    local error_count=0

    ux_section "Review Each File"
    for file in "${files[@]}"; do
        if ux_confirm "Delete $(basename "$file")?" "n"; then
            if _cleanup_delete_one "$file"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        else
            ux_info "Skipped: $file"
            skip_count=$((skip_count + 1))
        fi
    done

    ux_section "Summary"
    ux_success "$success_count file(s) deleted"
    ux_info "$skip_count file(s) skipped"
    if [ "$error_count" -gt 0 ]; then
        ux_warning "$error_count file(s) failed"
        return 1
    fi

    return 0
}

_cleanup_select_mode() {
    ux_section "Choose Deletion Mode"
    ux_bullet "1  Delete all matched files"
    ux_bullet "2  Review each matched file"
    ux_bullet "0  Cancel"

    while true; do
        printf "%s❯%s Select 0, 1, or 2: " "${UX_INFO}" "${UX_RESET}"
        read -r DEL_FILE_SELECTION
        case "$DEL_FILE_SELECTION" in
            0|1|2)
                return 0
                ;;
            *)
                ux_error "Invalid input. Enter 0, 1, or 2."
                ;;
        esac
    done
}

del_file() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        ux_error "del-file requires an interactive terminal"
        return 1
    fi

    local search_dir="${PWD}"
    local patterns=()
    local extra_pattern=""
    local default_pattern=""
    local selection=""

    _cleanup_set_default_patterns
    for default_pattern in "${CLEANUP_DEFAULT_PATTERNS[@]}"; do
        [ -n "$default_pattern" ] || continue
        patterns+=("$default_pattern")
    done

    for extra_pattern in "$@"; do
        [ -n "$extra_pattern" ] || continue
        patterns+=("$extra_pattern")
    done

    if ! _cleanup_preview "$search_dir" "${patterns[@]}"; then
        return 1
    fi

    ux_section "Deletion Modes"
    ux_bullet "Delete all   Delete every matched file after one confirmation"
    ux_bullet "Review each  Ask once per file before deleting"
    ux_bullet "Cancel       Do nothing"

    _cleanup_select_mode || return 0
    selection="$DEL_FILE_SELECTION"

    case "$selection" in
        1)
            _cleanup_delete_all "${DEL_FILE_MATCHED_FILES[@]}"
            ;;
        2)
            _cleanup_delete_individually "${DEL_FILE_MATCHED_FILES[@]}"
            ;;
        *)
            ux_info "Operation cancelled"
            return 0
            ;;
    esac
}

alias del-file='del_file'
