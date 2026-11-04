#!/bin/sh
# shell-common/env/dotenv.sh
# Load environment variables from .env file if it exists
# POSIX-compatible - sourced automatically by bash and zsh

# Determine DOTFILES_ROOT (prefer the SSOT exported by loaders)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

if [ -z "${DOTFILES_ROOT}" ] && [ -n "${SHELL_COMMON}" ]; then
    DOTFILES_ROOT="$(cd "${SHELL_COMMON}/.." 2>/dev/null && pwd)"
fi

# Source .env file if it exists
if [ -n "${DOTFILES_ROOT}" ] && [ -f "${DOTFILES_ROOT}/.env" ]; then
    env_file="${DOTFILES_ROOT}/.env"

    # shellcheck source=/dev/null
    if ! . "$env_file" 2>/dev/null; then
        # Only show error in debug mode to avoid polluting shell startup
        if [ "${DEBUG_DOTFILES:-0}" = "1" ]; then
            echo "Warning: Failed to source .env (check syntax)" >&2
        fi
    fi
fi
