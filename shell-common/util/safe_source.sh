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

safe_source() {
    local file_path="$1"
    local error_msg="${2:-File not found}"

    if [ ! -f "$file_path" ]; then
        # File doesn't exist - silently skip (common for optional files)
        return 0
    fi

    # Whether this file's stderr reaches the real stderr is decided up
    # front, from the path pattern + DEBUG_DOTFILES alone (issue #1504,
    # PR #1543 review) — never by buffering to a temp file and replaying
    # conditionally based on the exit code. Buffering was tried first but
    # forced one mktemp+rm subprocess pair per sourced file on every
    # interactive startup, changed stderr's live timing/ordering, and
    # needed two extra global helper functions just to manage the capture
    # file. Deciding the redirect target up front needs none of that:
    # `.local.sh` and non-debug "other" files always redirect to
    # /dev/null (their pre-existing fully-silent behavior, success or
    # failure alike); important files — the ones #1454's WARN actually
    # needed visible — are never redirected, so their stderr streams live
    # exactly like any other command's would.
    local _category
    case "$file_path" in
        *.local.sh) _category=local ;;
        */tools/integrations/* | */functions/* | */env/*) _category=important ;;
        *) _category=other ;;
    esac

    # Source file directly in parent shell (critical for function/alias
    # propagation) — NOTE: MUST NOT use $(...) subshell, it breaks
    # function definitions.
    if [ "$_category" = "local" ] || { [ "$_category" = "other" ] && [ "${DEBUG_DOTFILES:-0}" != "1" ]; }; then
        . "$file_path" 2>/dev/null
    else
        . "$file_path"
    fi
    local source_exit=$?

    if [ $source_exit -eq 0 ]; then
        # Increment counter after successful source
        SOURCED_FILES_COUNT=$((SOURCED_FILES_COUNT + 1))
        return 0
    fi

    # Source failed - report error for important files
    # Skip errors for optional files (like .local.sh)
    case "$_category" in
        local)
            # Optional local overrides - silently skip
            return 0
            ;;
        important)
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
