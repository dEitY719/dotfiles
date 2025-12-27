#!/bin/bash
# bash/util/init.bash
# Purpose: Initialize DOTFILES_BASH_DIR regardless of script location
# Usage: source ./util/init.bash (or relative path)
#        DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "${BASH_SOURCE[0]}")"
#        OR
#        eval "$(init_dotfiles_bash_dir_and_export "${BASH_SOURCE[0]}")"

init_dotfiles_bash_dir() {
    local script_path="$1"
    local script_dir

    # Get the real directory of the script (resolving symlinks)
    script_dir="$(dirname "$(realpath "$script_path")")"

    # Case 1: Script is directly in bash directory
    if [[ "$script_dir" == */bash ]] && [[ ! "$script_dir" == */bash/* ]]; then
        echo "$script_dir"
        return 0
    fi

    # Case 2: Script is in a subdirectory of bash (e.g., bash/util, bash/app, bash/env)
    if [[ "$script_dir" == */bash/* ]]; then
        echo "${script_dir%%/bash/*}/bash"
        return 0
    fi

    # Case 3: Script is in a sibling directory (e.g., mytool alongside bash)
    local parent_dir="$(dirname "$script_dir")"
    if [[ -d "$parent_dir/bash" ]]; then
        echo "$parent_dir/bash"
        return 0
    fi

    # Case 4: Fallback - search upward for bash directory
    local search_dir="$script_dir"
    while [[ "$search_dir" != "/" ]]; do
        if [[ -d "$search_dir/bash" ]]; then
            echo "$search_dir/bash"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done

    # Error: bash directory not found
    echo "ERROR: Could not find dotfiles bash directory from $script_path" >&2
    return 1
}

export -f init_dotfiles_bash_dir
