#!/bin/sh
# shell-common/env/dotenv.sh
# Load environment variables from .env file if it exists
# POSIX-compatible - sourced automatically by bash and zsh

# Determine DOTFILES_ROOT (prefer the SSOT exported by loaders)
if [ -z "${DOTFILES_ROOT}" ] && [ -n "${SHELL_COMMON}" ]; then
    DOTFILES_ROOT="$(cd "${SHELL_COMMON}/.." 2>/dev/null && pwd)"
fi

# Source .env file if it exists
if [ -n "${DOTFILES_ROOT}" ] && [ -f "${DOTFILES_ROOT}/.env" ]; then
    env_file="${DOTFILES_ROOT}/.env"

    # If repo is locked, git-crypt leaves encrypted bytes in the working tree.
    # Avoid sourcing binary data (causes: "syntax error near unexpected token `)'").
    # Check if file is encrypted by looking for GITCRYPT header using strings
    if head -c 20 "$env_file" 2>/dev/null | LC_ALL=C strings | grep -q "GITCRYPT"; then
        # File is encrypted - skip sourcing and suppress warning to avoid
        # Powerlevel10k instant prompt console output warning
        # Users can run 'git-crypt unlock' if they need .env variables
        :  # no-op (silent skip)
    else
        # File is decrypted - safe to source
        # shellcheck source=/dev/null
        . "$env_file" 2>/dev/null || true
    fi
fi
