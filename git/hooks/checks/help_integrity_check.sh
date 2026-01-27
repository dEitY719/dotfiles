#!/bin/bash
# git/hooks/checks/help_integrity_check.sh
# Checks for functions ending in 'help' that are not properly registered.
#
# Rule:
# Any function ending in 'help' (e.g., 'git-help', 'docker_help') is considered
# a public help topic and MUST be registered in HELP_DESCRIPTIONS.
# If it is an internal utility, it MUST start with '_' (e.g., '_register_help').

check_help_integrity() {
    local file="$1"
    local violations_file="$2"
    local repo_root="$3"

    # 1. Find function definitions ending in 'help'
    # Patterns to match:
    #   my_help() {
    #   function my_help {
    #   function my_help() {
    # We ignore leading whitespace.

    # Grep regex explanation:
    # ^[ 	]*              : Start of line, optional whitespace
    # (function[ 	]+)?    : Optional 'function' keyword
    # [a-zA-Z0-9_-]+help   : Name ending in 'help'
    # [ 	]*["({]          : Followed by '(' or '{'

    local func_names
    func_names=$(
        grep -E '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z0-9_-]+help[[:space:]]*(\\(\\))?[[:space:]]*\\{' "$file" |
            sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*\\(\\)[[:space:]]*\\{.*$//; s/[[:space:]]*\\{.*$//'
    )

    if [ -z "$func_names" ]; then
        return 0
    fi

    local my_help_path="$repo_root/shell-common/functions/my_help.sh"
    local fail=0

    while read -r func; do
        # Skip internal functions (start with _)
        if [[ "$func" == _* ]]; then
            continue
        fi

        # Check 1: Is it registered in the current file?
        # Look for: HELP_DESCRIPTIONS["func"]=... or HELP_DESCRIPTIONS[func]=...
        if grep -Eq "HELP_DESCRIPTIONS\\[(\"?${func}\"?)\\]" "$file"; then
            continue
        fi

        # Check 2: Is it registered in the global registry (my_help.sh)?
        if [ -f "$my_help_path" ] && grep -Eq "HELP_DESCRIPTIONS\\[(\"?${func}\"?)\\]" "$my_help_path"; then
            continue
        fi

        # Check 3: Is it registered with normalized name (underscores instead of dashes)?
        # e.g., func is "apt-help", but registered as "apt_help"
        local normalized="${func//-/_}"
        if [ "$func" != "$normalized" ]; then
            if grep -Eq "HELP_DESCRIPTIONS\\[(\"?${normalized}\"?)\\]" "$file"; then
                continue
            fi
            if [ -f "$my_help_path" ] && grep -Eq "HELP_DESCRIPTIONS\\[(\"?${normalized}\"?)\\]" "$my_help_path"; then
                continue
            fi
        fi

        # Violation found
        echo "$file: Public help function '$func' found without description." >> "$violations_file"
        echo "    -> Fix: Add HELP_DESCRIPTIONS[\"$func\"]=\"...\" OR rename to '_$func' if internal." >> "$violations_file"
        fail=1

    done <<< "$func_names"

    return $fail
}
