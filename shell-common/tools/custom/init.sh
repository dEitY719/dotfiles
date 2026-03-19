#!/bin/bash
# shell-common/tools/custom/init.sh
#
# Centralized initialization for all custom tools scripts.
# This resolves the SOLID principle violation where 21+ scripts had
# hardcoded relative paths. Now all initialization logic is in one place.
#
# Usage:
#   source "$(dirname "$0")/init.sh"

# Only initialize once
if [ -n "${_CUSTOM_TOOLS_INITIALIZED:-}" ]; then
    return 0
fi

# Exit early in test mode (prevents side effects like package installations)
if [ "${DOTFILES_TEST_MODE:-0}" = "1" ]; then
    _CUSTOM_TOOLS_INITIALIZED=1
    return 0
fi

# Define minimal UX fallback BEFORE validation (in case UX library fails to load)
# This prevents "command not found" errors in error paths
if ! type ux_error >/dev/null 2>&1; then
    ux_error() { echo "Error:" "$@" >&2; }
    ux_info() { echo "Info:" "$@"; }
    ux_success() { echo "Success:" "$@"; }
fi

# Detect DOTFILES_ROOT dynamically (shell-specific sourced script detection)
# Works regardless of where this script is called from
# In sourced scripts, $0 is unreliable, so we use shell-specific methods:
# - bash: BASH_SOURCE[0] points to the sourced script
# - zsh: ${(%):-%N} points to the sourced script
# - fallback: attempt to use $0 with dirname

if [ -n "$BASH_VERSION" ]; then
    # Running in bash: use BASH_SOURCE for accurate location
    _THIS_SCRIPT="${BASH_SOURCE[0]}"
elif [ -n "$ZSH_VERSION" ]; then
    # Running in zsh: use parameter expansion for accurate location
    _THIS_SCRIPT="${(%):-%N}"
else
    # Fallback for other POSIX shells
    _THIS_SCRIPT="$0"
fi

_THIS_DIR="$(cd "$(dirname "$_THIS_SCRIPT")" && pwd)"

# Navigate from shell-common/tools/custom back to dotfiles root
# Path: /path/to/dotfiles/shell-common/tools/custom/init.sh
#       Remove: shell-common/tools/custom/ (3 path components)
DOTFILES_ROOT="${_THIS_DIR%/shell-common/tools/custom}"

# Validate DOTFILES_ROOT
if [ ! -d "$DOTFILES_ROOT" ] || [ ! -d "$DOTFILES_ROOT/bash" ]; then
    ux_error "Failed to detect DOTFILES_ROOT. Expected structure:" >&2
    echo "   $DOTFILES_ROOT/bash/" >&2
    echo "   $DOTFILES_ROOT/shell-common/" >&2
    return 1
fi

# Set derived paths
export DOTFILES_ROOT
export DOTFILES_BASH_DIR="${DOTFILES_ROOT}/bash"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Load UX library (if not already loaded, replace fallback with real implementation)
if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    # UX library loaded successfully (fallback already replaced)
fi

# Shared utility functions (SSOT: used by check_network.sh, check_proxy.sh, etc.)
have_command() {
    command -v "$1" >/dev/null 2>&1
}

run_with_timeout() {
    local seconds="$1"
    shift

    if have_command timeout; then
        timeout "$seconds" "$@"
        return $?
    fi

    if have_command gtimeout; then
        gtimeout "$seconds" "$@"
        return $?
    fi

    "$@"
}

# Mark as initialized to prevent re-sourcing
_CUSTOM_TOOLS_INITIALIZED=1

# Direct-exec guard: this file is source-only, not meant to be executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    echo "Error: init.sh is meant to be sourced, not executed directly." >&2
    echo "Usage: source \"\$(dirname \"\$0\")/init.sh\"" >&2
    exit 1
fi
