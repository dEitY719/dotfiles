#!/bin/sh
# shell-common/functions/init_summary.sh
#
# Shared initialization summary function for bash and zsh
# Follows SOLID principles: Single Responsibility Principle (SRP)
# - Only responsible for displaying initialization completion message
# - Decoupled from shell-specific counting logic
# - Reusable across any shell implementation

# Display dotfiles initialization summary
#
# Usage:
#   dotfiles_init_summary <file_count>
#
# Parameters:
#   $1 - Number of files sourced during initialization
#
# Note: Requires UX library (ux_lib.sh) to be loaded for consistent styling
#
dotfiles_init_summary() {
    local file_count="${1:-0}"

    # Display the success message
    echo "Dotfiles configuration loaded successfully. (Total files sourced: ${file_count})"
}
