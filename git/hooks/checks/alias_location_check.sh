#!/usr/bin/env bash
# git/hooks/checks/alias_location_check.sh
# Ensure aliases are in shell-common/aliases/, not shell-common/functions/
# Ensure functions don't get mixed into alias files

check_alias_location() {
    local repo_root="$1"
    local tmpdir="$2"
    local file="$3"
    local output_file="$4"

    local abs_path="${repo_root}/${file}"
    [ -f "$abs_path" ] || return 0

    # Exclude legacy files that intentionally mix aliases and functions
    # (e.g., my_help.sh where the alias is tightly coupled to the function)
    case "$file" in
        shell-common/functions/my_help.sh) return 0 ;;
    esac

    # Check 1: Aliases in shell-common/functions/ (WRONG LOCATION)
    # BUT: only for files NOT already in git (i.e., newly created files)
    if [[ "$file" == shell-common/functions/*.sh ]]; then
        # Skip if file is already tracked in git (pre-existing)
        if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
            return 0  # File already in git, skip check
        fi

        if grep -q "^[[:space:]]*alias[[:space:]]" "$abs_path"; then
            {
                echo "${file}:"
                echo "  ERROR: Aliases found in shell-common/functions/ (wrong location)"
                echo "  SOLUTION: Move aliases to shell-common/aliases/ directory"
                echo "  EXAMPLES:"
                grep -n "^[[:space:]]*alias[[:space:]]" "$abs_path" | head -3 | sed 's/^/    /'
            } >> "$output_file"
            return 1
        fi
    fi

    # Check 2: Functions in shell-common/aliases/ (WRONG LOCATION)
    if [[ "$file" == shell-common/aliases/*.sh ]]; then
        # Skip if file is already tracked in git
        if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
            return 0  # File already in git, skip check
        fi

        # Look for function definitions (but allow aliases and comments)
        if grep -q "^[a-zA-Z_][a-zA-Z0-9_]*()[[:space:]]*{" "$abs_path" || \
           grep -q "^function[[:space:]]\+[a-zA-Z_]" "$abs_path"; then
            {
                echo "${file}:"
                echo "  ERROR: Functions found in shell-common/aliases/ (wrong location)"
                echo "  SOLUTION: Move functions to shell-common/functions/ directory"
            } >> "$output_file"
            return 1
        fi
    fi

    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "This script should be sourced, not executed directly"
    exit 1
fi
