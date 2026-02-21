#!/usr/bin/env bash
# git/hooks/checks/shellcheck_check.sh
# ShellCheck static analysis for shell scripts
#
# Detects:
# - Tilde expansion issues (SC2088)
# - Quoting problems
# - Variable expansion issues
# - Best practice violations

# Skip if shellcheck not available
if ! command -v shellcheck &>/dev/null; then
    return 0
fi

check_shellcheck() {
    local shellcheck_violations_file="$1"
    local staged_files="$2"

    local total_violations=0

    # Run shellcheck on all bash/sh files
    while IFS= read -r file; do
        # Skip non-shell files
        case "$file" in
            *.sh | *.bash | *.zsh)
                ;;
            *)
                # Check shebang for shell scripts
                if head -1 "$file" 2>/dev/null | grep -qE '^#!.*\b(bash|sh|zsh)'; then
                    :  # Continue checking
                else
                    continue
                fi
                ;;
        esac

        # Run shellcheck with strict rules for shell-common (portable sh)
        # and default rules for others
        local shellcheck_args="-S warning"
        if [[ "$file" == shell-common/* ]]; then
            # Stricter for shell-common: enforce sh compatibility
            shellcheck_args="-S info -x"  # -x enables sourceability check
        fi

        if ! shellcheck $shellcheck_args "$file" 2>&1 | grep -v "^$" | while read -r line; do
            echo "$file: $line" >> "$shellcheck_violations_file"
        done; then
            :  # shellcheck can return non-zero, that's ok
        fi

    done <<< "$staged_files"

    # Report violations if any exist
    if [ -f "$shellcheck_violations_file" ] && [ -s "$shellcheck_violations_file" ]; then
        echo -e "${YELLOW}[ShellCheck] Found potential issues:${NC}"
        head -20 "$shellcheck_violations_file" | sed 's/^/  /'
        total_violations=$(wc -l < "$shellcheck_violations_file")

        if [ "$total_violations" -gt 20 ]; then
            echo "  ... and $((total_violations - 20)) more"
        fi

        return 1
    fi

    return 0
}

# Run the check if this script is sourced
if [ -z "$_SHELLCHECK_CHECK_SOURCED" ]; then
    _SHELLCHECK_CHECK_SOURCED=1

    # Only run if we have violations file and staged files
    if [ -n "$SHELLCHECK_VIOLATIONS_FILE" ] && [ -n "$STAGED_FILES" ]; then
        check_shellcheck "$SHELLCHECK_VIOLATIONS_FILE" "$STAGED_FILES"
    fi
fi
