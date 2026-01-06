#!/bin/sh
# shell-common/functions/init_summary.sh
#
# Shared initialization summary function for bash and zsh
# Follows SOLID principles: Single Responsibility Principle (SRP)
# - Only responsible for displaying initialization completion message
# - Decoupled from shell-specific counting logic
# - Reusable across any shell implementation
# - Routes through UX library for consistent styling

# Display dotfiles initialization summary
#
# Usage:
#   dotfiles_init_summary <file_count>
#
# Parameters:
#   $1 - Number of files sourced during initialization
#
# Note: Uses UX library (ux_lib.sh) if available for consistent styling
#
dotfiles_init_summary() {
    local file_count="${1:-0}"
    local message="Dotfiles configuration loaded successfully. (Total files sourced: ${file_count})"

    # Route through UX library if available for consistency
    if type ux_success >/dev/null 2>&1; then
        ux_success "$message"
    else
        # Fallback to raw echo if UX library not loaded
        echo "$message"
    fi
}
