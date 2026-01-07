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

# Detect DOTFILES_ROOT dynamically (POSIX-compatible for bash/zsh)
# Works regardless of where this script is called from
# Get this script's directory using POSIX-compatible approach
# Works in bash, zsh, and other POSIX shells
_THIS_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# Mark as initialized to prevent re-sourcing
_CUSTOM_TOOLS_INITIALIZED=1
