#!/bin/bash
# Check UX consistency across all bash files

# Initialize paths using unified path resolution
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_SCRIPT_DIR="$(dirname "$_SCRIPT_PATH")"

# Navigate from shell-common/tools/custom to DOTFILES_ROOT
SHELL_COMMON="${_SCRIPT_DIR%/tools/custom}"
export SHELL_COMMON
DOTFILES_ROOT="${SHELL_COMMON%/shell-common}"
export DOTFILES_ROOT
DOTFILES_BASH_DIR="${DOTFILES_ROOT}/bash"
export DOTFILES_BASH_DIR

# Load UX library for reporting
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

main() {
    ux_header "UX Consistency Checker"
    local total_issues=0

# =============================================================================
# Check 1: Find deprecated raw `tput` color definitions
# =============================================================================
ux_section "1. Checking for deprecated color definitions"
# shellcheck disable=SC2016  # literal grep patterns — '$(tput ...)' must stay unexpanded
deprecated_patterns=(
    'bold=$(tput bold'
    'blue=$(tput setaf 4'
    'green=$(tput setaf 2'
    'yellow=$(tput setaf 3'
    'red=$(tput setaf 1'
    'reset=$(tput sgr0'
)

found_files=""
# Search the shell source trees (bash/, zsh/, shell-common/) that exist.
# Paths are relative to DOTFILES_ROOT so the tmp/.git exclusions below never
# match components of the checkout's own absolute path (e.g. a clone under /tmp).
search_dirs=()
for dir in bash zsh shell-common; do
    [ -d "${DOTFILES_ROOT}/${dir}" ] && search_dirs+=("$dir")
done
scanned_count=0
if [ "${#search_dirs[@]}" -gt 0 ]; then
    scanned_count=$(cd "$DOTFILES_ROOT" && find "${search_dirs[@]}" -type f \
        -not -path '*/ux_lib/*' -not -path '*/.git/*' -not -path '*/.idea/*' \
        -not -path '*/tmp/*' -not -name 'check_ux_consistency.sh' | wc -l)
fi
ux_info "Scanned ${scanned_count// /} file(s)"
if [ "$scanned_count" -eq 0 ]; then
    ux_error "No files scanned: search directories are missing or empty."
    total_issues=$((total_issues + 1))
else
    for pattern in "${deprecated_patterns[@]}"; do
        # Exclude ux_lib itself, this script, and binary files
        found_files+=$(cd "$DOTFILES_ROOT" || exit 0; grep -r -l -F "$pattern" "${search_dirs[@]}" \
            --exclude-dir="ux_lib" \
            --exclude-dir=".git" \
            --exclude-dir=".idea" \
            --exclude-dir="tmp" \
            --exclude="check_ux_consistency.sh" 2>/dev/null || true)
        found_files+=$'\n'
    done
fi

# Process unique files found
unique_files=$(echo "$found_files" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u)

if [ -z "$unique_files" ]; then
    ux_success "No deprecated color definitions found."
else
    ux_error "Found files with deprecated color definitions:"
    while IFS= read -r file; do
        ux_bullet "$file"
    done <<< "$unique_files"
    total_issues=$((total_issues + $(echo "$unique_files" | wc -l)))
fi


# =============================================================================
# Check 2: Ensure Python helper scripts are executable
# =============================================================================
ux_section "2. Checking Python helper script permissions"
py_script_issues=0
# The python scripts used by ux_lib are in ux_lib
py_scripts_dir="${SHELL_COMMON}/tools/ux_lib"
for py_script in "${py_scripts_dir}/"*.py; do
    if [ -f "$py_script" ] && [ ! -x "$py_script" ]; then
        ux_warning "Python script '$py_script' is not executable. Run 'chmod +x $py_script'"
        ((py_script_issues++))
    fi
done

if [ "$py_script_issues" -eq 0 ]; then
    ux_success "All internal Python scripts have correct execute permissions."
else
    ux_error "Found $py_script_issues Python scripts without execute permissions."
    total_issues=$((total_issues + py_script_issues))
fi


    # =============================================================================
    # Summary
    # =============================================================================
    ux_divider_thick
    if [ "$total_issues" -eq 0 ]; then
        ux_success "All UX consistency checks passed!"
        return 0
    else
        ux_error "Found $total_issues total UX consistency issue(s)."
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Direct-Execution Guard
# ═══════════════════════════════════════════════════════════════
# Only run main() if this script is executed directly, not sourced
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
