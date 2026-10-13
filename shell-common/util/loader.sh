#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/util/loader.sh
# Category module loader
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
LOADER_DEBUG="${DEBUG_DOTFILES:-0}"

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

# Functions are available in sourcing script context (no explicit export needed)
