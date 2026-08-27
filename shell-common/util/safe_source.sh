#!/bin/sh
# shell-common/util/safe_source.sh
# SSOT for safe file sourcing with counter tracking
# Sourced by both bash/main.bash and zsh/main.zsh
#
# Must be sourced BEFORE any safe_source() calls.
# Counter SOURCED_FILES_COUNT must be initialized by the caller:
#   bash: declare -gi SOURCED_FILES_COUNT=0
#   zsh:  typeset -gi SOURCED_FILES_COUNT=0

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# _safe_source_discard_capture CAPTURE_FILE
#
# Remove CAPTURE_FILE without printing it. No-op when CAPTURE_FILE is empty
# (mktemp failed upstream, so there was never anything to capture).
_safe_source_discard_capture() {
    [ -n "$1" ] && rm -f "$1"
}

# _safe_source_flush_capture CAPTURE_FILE
#
# Emit CAPTURE_FILE's content to the real stderr (if non-empty), then
# remove it.
_safe_source_flush_capture() {
    [ -n "$1" ] && [ -s "$1" ] && cat "$1" >&2
    _safe_source_discard_capture "$1"
}

safe_source() {
    local file_path="$1"
    local error_msg="${2:-File not found}"

    if [ ! -f "$file_path" ]; then
        # File doesn't exist - silently skip (common for optional files)
        return 0
    fi

    # Capture stderr instead of discarding it outright (issue #1504): a
    # successfully-sourced file's own stderr output (e.g. #1454's
    # foreign-checkout WARN) must still reach the user, not just an error
    # path. Falls back to the old discard-everything behavior if mktemp
    # itself fails.
    local stderr_capture
    stderr_capture=$(mktemp 2>/dev/null) || stderr_capture=""

    # Source file directly in parent shell (critical for function/alias propagation)
    # NOTE: MUST NOT use $(...) subshell as it breaks function definitions
    if [ -n "$stderr_capture" ]; then
        . "$file_path" 2>"$stderr_capture"
    else
        . "$file_path" 2>/dev/null
    fi
    local source_exit=$?

    if [ $source_exit -eq 0 ]; then
        # Increment counter after successful source
        SOURCED_FILES_COUNT=$((SOURCED_FILES_COUNT + 1))
        _safe_source_flush_capture "$stderr_capture"
        return 0
    fi

    # Source failed - report error for important files
    # Skip errors for optional files (like .local.sh)
    case "$file_path" in
        *.local.sh)
            # Optional local overrides - silently skip, capture included
            _safe_source_discard_capture "$stderr_capture"
            return 0
            ;;
        */tools/integrations/*|*/functions/*|*/env/*)
            # Important files - report error, plus whatever the failed
            # source itself wrote to stderr (e.g. a syntax error)
            if type ux_error >/dev/null 2>&1; then
                ux_error "${error_msg}: ${file_path}"
            else
                echo "Error: ${error_msg}: ${file_path}" >&2
            fi
            _safe_source_flush_capture "$stderr_capture"
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
                _safe_source_flush_capture "$stderr_capture"
            else
                _safe_source_discard_capture "$stderr_capture"
            fi
            return 1
            ;;
    esac
}
