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
if [[ -n "$_CUSTOM_TOOLS_INITIALIZED" ]]; then
    return 0
fi

# Detect DOTFILES_ROOT dynamically
# Works regardless of where this script is called from
_THIS_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
_THIS_DIR="$(dirname "$_THIS_SCRIPT")"

# Navigate from shell-common/tools/custom back to dotfiles root
# Path: /path/to/dotfiles/shell-common/tools/custom/init.sh
#       Remove: shell-common/tools/custom/init.sh (4 path components)
DOTFILES_ROOT="${_THIS_DIR%/shell-common/tools/custom}"

# Validate DOTFILES_ROOT
if [[ ! -d "$DOTFILES_ROOT" ]] || [[ ! -d "$DOTFILES_ROOT/bash" ]]; then
    echo "❌ Error: Could not detect DOTFILES_ROOT. Expected structure:" >&2
    echo "   $DOTFILES_ROOT/bash/" >&2
    echo "   $DOTFILES_ROOT/shell-common/" >&2
    return 1
fi

# Set derived paths
export DOTFILES_ROOT
export DOTFILES_BASH_DIR="${DOTFILES_ROOT}/bash"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Load UX library
if [[ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]]; then
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
else
    # Fallback: define minimal error handling if UX library unavailable
    ux_error() { echo "❌ $*" >&2; }
    ux_info() { echo "ℹ️  $*"; }
    ux_success() { echo "✓ $*"; }
fi

# Mark as initialized to prevent re-sourcing
_CUSTOM_TOOLS_INITIALIZED=1
