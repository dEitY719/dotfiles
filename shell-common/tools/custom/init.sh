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

# Detect DOTFILES_ROOT dynamically (bash-specific due to BASH_SOURCE)
# Works regardless of where this script is called from
# Use -- to prevent "-bash" or similar values from being interpreted as options
_THIS_SCRIPT="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
_THIS_DIR="$(dirname -- "$_THIS_SCRIPT")"

# Navigate from shell-common/tools/custom back to dotfiles root
# Path: /path/to/dotfiles/shell-common/tools/custom/init.sh
#       Remove: shell-common/tools/custom/ (3 path components)
DOTFILES_ROOT="${_THIS_DIR%/shell-common/tools/custom}"

# Validate DOTFILES_ROOT
if [ ! -d "$DOTFILES_ROOT" ] || [ ! -d "$DOTFILES_ROOT/bash" ]; then
    # UX library not yet loaded, use basic error output
    ux_error "Failed to detect DOTFILES_ROOT. Expected structure:" >&2
    echo "   $DOTFILES_ROOT/bash/" >&2
    echo "   $DOTFILES_ROOT/shell-common/" >&2
    return 1
fi

# Set derived paths
export DOTFILES_ROOT
export DOTFILES_BASH_DIR="${DOTFILES_ROOT}/bash"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Load UX library
if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
else
    # Fallback: define minimal UX functions if library unavailable
    ux_error() { echo "Error:" "$@" >&2; }
    ux_info() { echo "Info:" "$@"; }
    ux_success() { echo "Success:" "$@"; }
fi

# Mark as initialized to prevent re-sourcing
_CUSTOM_TOOLS_INITIALIZED=1
