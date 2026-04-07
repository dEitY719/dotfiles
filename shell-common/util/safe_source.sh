#!/bin/sh
# shell-common/util/safe_source.sh
# SSOT for safe file sourcing with counter tracking
# Sourced by both bash/main.bash and zsh/main.zsh
#
# Must be sourced BEFORE any safe_source() calls.
# Counter SOURCED_FILES_COUNT must be initialized by the caller:
#   bash: declare -gi SOURCED_FILES_COUNT=0
#   zsh:  typeset -gi SOURCED_FILES_COUNT=0

safe_source() {
    local file_path="$1"
    local error_msg="${2:-File not found}"

    if [ ! -f "$file_path" ]; then
        # File doesn't exist - silently skip (common for optional files)
        return 0
    fi

    # Source file directly in parent shell (critical for function/alias propagation)
    # NOTE: MUST NOT use $(...) subshell as it breaks function definitions
    . "$file_path" 2>/dev/null
    local source_exit=$?

    if [ $source_exit -eq 0 ]; then
        # Increment counter after successful source
        ((++SOURCED_FILES_COUNT))
        return 0
    fi

    # Source failed - report error for important files
    # Skip errors for optional files (like .local.sh)
    case "$file_path" in
        *.local.sh)
            # Optional local overrides - silently skip
            return 0
            ;;
        */tools/integrations/*|*/functions/*|*/env/*)
            # Important files - report error
            if type ux_error >/dev/null 2>&1; then
                ux_error "${error_msg}: ${file_path}"
            else
                echo "Error: ${error_msg}: ${file_path}" >&2
            fi
            return 1
            ;;
        *)
            # Other files - report error only in debug mode
            if [ "${DEBUG_DOTFILES:-0}" = "1" ]; then
                if type ux_error >/dev/null 2>&1; then
                    ux_error "${error_msg}: ${file_path}"
                else
                    echo "Error: ${error_msg}: ${file_path}" >&2
                fi
            fi
            return 1
            ;;
    esac
}
