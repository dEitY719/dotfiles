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
    if dd if="$env_file" bs=1 count=8 2>/dev/null | LC_ALL=C grep -q "^GITCRYPT"; then
        # File is encrypted - skip sourcing and suppress warning to avoid
        # Powerlevel10k instant prompt console output warning
        # Users can run 'git-crypt unlock' if they need .env variables
        :  # no-op
    else
        # File is decrypted - safe to source
        # shellcheck source=/dev/null
        . "$env_file"
    fi
fi
