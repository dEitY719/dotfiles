#!/bin/sh
# shell-common/util/path_resolver.sh
# POSIX-compliant path resolution for both bash and zsh
# Centralizes DOTFILES_ROOT detection to avoid duplication

# Direct-exec guard: This file should be sourced, not executed
if [ "${0##*/}" != "path_resolver.sh" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This file should be sourced, not executed directly" >&2
    exit 1
fi

# Resolve DOTFILES_ROOT from the sourcing context
# Works with both bash and zsh through BASH_SOURCE / ZSH_VERSION detection
resolve_dotfiles_root() {
    local script_path=""
    local script_dir=""

    # Detect shell and get script path accordingly
    if [[ -n "${BASH_VERSION}" ]]; then
        # Bash: Use BASH_SOURCE[1] (caller's file)
        script_path="${BASH_SOURCE[1]}"
    elif [[ -n "${ZSH_VERSION}" ]]; then
        # Zsh: Use special substitution to get script location
        script_path="${(%):-%N}"
    else
        # Fallback for other shells
        script_path="${0}"
    fi

    # Get directory of the script
    script_dir="$(cd "$(dirname "${script_path}")" 2>/dev/null && pwd)" || return 1

    # Navigate up to dotfiles root
    # Assumes this file is at: {DOTFILES_ROOT}/shell-common/util/path_resolver.sh
    # So we go up 3 levels: util -> shell-common -> DOTFILES_ROOT
    local dotfiles_root="${script_dir%/util*}"

    # Validate: Check if DOTFILES_ROOT looks valid (has shell-common subdirectory)
    if [[ -d "${dotfiles_root}/shell-common" ]]; then
        echo "${dotfiles_root}"
        return 0
    fi

    # Fallback to direct parent check (if called from main.bash/main.zsh)
    dotfiles_root="${script_dir%/shell-common/util}"
    if [[ -d "${dotfiles_root}/shell-common" ]]; then
        echo "${dotfiles_root}"
        return 0
    fi

    # Last resort: try HOME/dotfiles
    if [[ -d "${HOME}/dotfiles/shell-common" ]]; then
        echo "${HOME}/dotfiles"
        return 0
    fi

    return 1
}

# Export the function for use by sourcing scripts
export -f resolve_dotfiles_root
