#!/bin/bash
# Commit message validator functions
# Used by: git/hooks/commit-msg
# Purpose: Validate messages against Conventional Commits rules

set -o errexit
set -o pipefail

# Import rules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config/commit-msg-rules.sh"

# ============================================
# VALIDATION FUNCTIONS
# ============================================

# Validate if message is empty
validate_not_empty() {
    local msg="$1"
    if [ -z "$msg" ] || [ "$msg" = "" ]; then
        echo "$MSG_EMPTY"
        return 1
    fi
    return 0
}

# Check if message matches forbidden patterns
validate_no_forbidden_patterns() {
    local msg="$1"
    local first_line="${msg%%$'\n'*}"

    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        if [[ "$first_line" =~ $pattern ]]; then
            echo "$MSG_FORBIDDEN"
            return 1
        fi
    done
    return 0
}

# Validate commit type (feat:, fix:, etc.)
validate_commit_type() {
    local msg="$1"
    local first_line="${msg%%$'\n'*}"

    # Extract type (word before the colon)
    local type="${first_line%%(*}"      # Remove scope if present (feat(scope)...)
    type="${type%%:*}"                  # Get word before colon
    type="${type#/}"                    # Remove leading slash if any
    type="${type%% }"                   # Trim trailing spaces

    # Check if type is valid
    local valid=0
    for allowed_type in "${COMMIT_TYPES[@]}"; do
        if [ "$type" = "$allowed_type" ]; then
            valid=1
            break
        fi
    done

    if [ $valid -eq 0 ]; then
        echo "$MSG_INVALID_TYPE"
        return 1
    fi
    return 0
}

# Validate subject line length
validate_subject_length() {
    local msg="$1"
    local first_line="${msg%%$'\n'*}"
    local length=${#first_line}

    if [ "$length" -lt "$MIN_MESSAGE_LENGTH" ]; then
        echo "$MSG_SUBJECT_TOO_SHORT"
        return 1
    fi

    if [ "$length" -gt "$SUBJECT_MAX_LENGTH" ]; then
        echo "$MSG_SUBJECT_TOO_LONG"
        return 1
    fi
    return 0
}

# Validate body line lengths
validate_body_length() {
    local msg="$1"
    local lines=()

    # Split message into lines
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$msg"

    # Skip first line (subject) - line 0
    # Line 1 should be empty (separator)
    # Lines 2+ are body

    for i in "${!lines[@]}"; do
        if [ "$i" -gt 1 ]; then
            # Skip comment lines and empty lines in body
            if [[ "${lines[$i]}" != "#"* ]] && [ -n "${lines[$i]}" ]; then
                if [ ${#lines[$i]} -gt "$BODY_MAX_LENGTH" ]; then
                    echo "$MSG_BODY_TOO_LONG"
                    return 1
                fi
            fi
        fi
    done
    return 0
}

# Check if body exists (optional, but warn if only subject)
validate_multi_line_format() {
    local msg="$1"
    local line_count=$(echo "$msg" | wc -l)

    # If message has more than 1 line, check separator
    if [ "$line_count" -gt 1 ]; then
        local second_line=$(echo "$msg" | sed -n '2p')
        if [ -n "$second_line" ]; then
            echo "$MSG_NO_SEPARATOR"
            return 1
        fi
    fi
    return 0
}

# ============================================
# MAIN VALIDATION FUNCTION
# ============================================

validate_commit_message() {
    local msg="$1"
    local errors=""

    # Run all validations
    if ! output=$(validate_not_empty "$msg"); then
        errors="${errors}${output}\n"
    fi

    if ! output=$(validate_no_forbidden_patterns "$msg"); then
        errors="${errors}${output}\n"
    fi

    if ! output=$(validate_commit_type "$msg"); then
        errors="${errors}${output}\n"
    fi

    if ! output=$(validate_subject_length "$msg"); then
        errors="${errors}${output}\n"
    fi

    if ! output=$(validate_body_length "$msg"); then
        errors="${errors}${output}\n"
    fi

    if ! output=$(validate_multi_line_format "$msg"); then
        errors="${errors}${output}\n"
    fi

    # Print all errors
    if [ -n "$errors" ]; then
        printf '%b' "$errors"
        return 1
    fi

    return 0
}

# Only run if sourced with function name as argument
if [ $# -gt 0 ]; then
    "$@"
fi
