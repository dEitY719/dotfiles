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
deprecated_patterns=(
    'bold=$(tput bold'
    'blue=$(tput setaf 4'
    'green=$(tput setaf 2'
    'yellow=$(tput setaf 3'
    'red=$(tput setaf 1'
    'reset=$(tput sgr0'
)

found_files=""
# Search in app/, alias/, and coreutils/ directories
search_dirs=(
    "${DOTFILES_BASH_DIR}/app"
    "${DOTFILES_BASH_DIR}/alias"
    "${DOTFILES_BASH_DIR}/coreutils"
    "${SCRIPT_DIR}"
)

for pattern in "${deprecated_patterns[@]}"; do
    # Exclude ux_lib itself, this script, and binary files
    found_files+=$(grep -r -l -E "$pattern" "${search_dirs[@]}" \
        --exclude-dir="ux_lib" \
        --exclude-dir=".git" \
        --exclude-dir=".idea" \
        --exclude-dir="tmp" \
        --exclude="check_ux_consistency.sh" 2>/dev/null || true)
    found_files+=$'\n'
done

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
py_scripts_dir="${DOTFILES_BASH_DIR}/ux_lib"
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
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
