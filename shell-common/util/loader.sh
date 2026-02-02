#!/bin/sh
# shell-common/util/loader.sh
# Module loader with configuration-based directory filtering
# Centralizes module loading logic for both bash and zsh
#
# Usage:
#   source shell-common/util/loader.sh
#   load_category "env"     # Load all .sh in shell-common/env/
#   load_category "aliases" # Load all .sh in shell-common/aliases/

# Direct-exec guard: This file should be sourced, not executed
if [ "${0##*/}" != "loader.sh" ] && [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This file should be sourced, not executed directly" >&2
    exit 1
fi

# Configuration
LOADER_SKIP_CONF="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/config/loader.conf"
LOADER_DEBUG="${DEBUG_DOTFILES:-0}"

# Parse skip list from configuration file
_load_skip_list() {
    if [ ! -f "$LOADER_SKIP_CONF" ]; then
        return 0
    fi

    # Read skip config, ignore comments and empty lines
    sed 's/#.*//' "$LOADER_SKIP_CONF" | sed '/^[[:space:]]*$/d'
}

# Check if directory should be skipped
_should_skip_dir() {
    local dir_name="$1"
    local skip_list

    skip_list=$(_load_skip_list)

    # Check if dir_name is in skip list
    echo "$skip_list" | grep -qx "$dir_name"
}

# Load all .sh files from a category directory
load_category() {
    local category="$1"
    local base_dir="${2:-${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}}"
    local category_dir="${base_dir}/${category}"

    if [ ! -d "$category_dir" ]; then
        if [ "$LOADER_DEBUG" = "1" ]; then
            echo "DEBUG: Category directory not found: $category_dir" >&2
        fi
        return 1
    fi

    if [ "$LOADER_DEBUG" = "1" ]; then
        echo "DEBUG: Loading category: $category from $category_dir" >&2
    fi

    # Count loaded files
    local count=0
    for f in "${category_dir}"/*.sh; do
        [ -f "$f" ] || continue

        # Skip .local.sh files (user overrides, not auto-loaded)
        case "$f" in
        *.local.sh) continue ;;
        esac

        # Source file
        if [ -n "${ZSH_VERSION}" ]; then
            # Zsh: use dot command for consistency
            . "$f" 2>/dev/null
        else
            # Bash/sh: use source or dot
            . "$f" 2>/dev/null
        fi

        count=$((count + 1))

        if [ "$LOADER_DEBUG" = "1" ]; then
            echo "DEBUG: Loaded: $f" >&2
        fi
    done

    if [ "$LOADER_DEBUG" = "1" ]; then
        echo "DEBUG: Category '$category': $count files loaded" >&2
    fi
}

# Load all directories in bash/dotfiles (excluding skip list)
load_auto_directories() {
    local base_dir="$1"
    local extension="${2:-.bash}"  # Default to .bash files
    local count=0

    if [ ! -d "$base_dir" ]; then
        return 0
    fi

    if [ "$LOADER_DEBUG" = "1" ]; then
        echo "DEBUG: Auto-loading from $base_dir" >&2
    fi

    # Iterate through directories
    for dir in "${base_dir}"/*; do
        [ -d "$dir" ] || continue

        local dir_name
        dir_name=$(basename "$dir")

        # Check skip list
        if _should_skip_dir "$dir_name"; then
            if [ "$LOADER_DEBUG" = "1" ]; then
                echo "DEBUG: Skipping directory: $dir_name" >&2
            fi
            continue
        fi

        # Load all files with extension
        for f in "${dir}"/*"${extension}"; do
            [ -f "$f" ] || continue

            . "$f" 2>/dev/null
            count=$((count + 1))

            if [ "$LOADER_DEBUG" = "1" ]; then
                echo "DEBUG: Loaded: $f" >&2
            fi
        done
    done

    if [ "$LOADER_DEBUG" = "1" ]; then
        echo "DEBUG: Auto-loaded $count files from $base_dir" >&2
    fi
}

# Functions are available in sourcing script context (no explicit export needed)
