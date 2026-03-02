#!/bin/sh
# shell-common/env/dotenv.sh
# Load environment variables from .env file if it exists
# POSIX-compatible - sourced automatically by bash and zsh

# Determine DOTFILES_ROOT (prefer the SSOT exported by loaders)
if [ -z "${DOTFILES_ROOT}" ] && [ -n "${SHELL_COMMON}" ]; then
    DOTFILES_ROOT="$(cd "${SHELL_COMMON}/.." 2>/dev/null && pwd)"
fi

# Check if file is encrypted by git-crypt (supports multiple detection methods)
_is_gitcrypt_encrypted() {
    local file="$1"

    # Method 1: strings command (preferred)
    if command -v strings >/dev/null 2>&1; then
        head -c 20 "$file" 2>/dev/null | LC_ALL=C strings | grep -q "GITCRYPT"
        return $?
    fi

    # Method 2: Fallback - od command
    if command -v od >/dev/null 2>&1; then
        # Check for GITCRYPT in hex: 47 49 54 43 52 59 50 54
        head -c 20 "$file" 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -q "474954435259"
        return $?
    fi

    # Method 3: Last resort - file command
    if command -v file >/dev/null 2>&1; then
        # Encrypted files appear as "data"
        file "$file" 2>/dev/null | grep -q "data"
        return $?
    fi

    # Unable to detect - assume not encrypted (safe default for sourcing)
    return 1
}

# Source .env file if it exists
if [ -n "${DOTFILES_ROOT}" ] && [ -f "${DOTFILES_ROOT}/.env" ]; then
    env_file="${DOTFILES_ROOT}/.env"

    # If repo is locked, git-crypt leaves encrypted bytes in the working tree.
    # Avoid sourcing binary data (causes: "syntax error near unexpected token `)'").
    if _is_gitcrypt_encrypted "$env_file"; then
        # File is encrypted - skip sourcing and suppress warning to avoid
        # Powerlevel10k instant prompt console output warning
        # Users can run 'git-crypt unlock' if they need .env variables
        :  # no-op (silent skip)
    else
        # File is decrypted - safe to source
        # shellcheck source=/dev/null
        if ! . "$env_file" 2>/dev/null; then
            # Only show error in debug mode to avoid polluting shell startup
            if [ "${DEBUG_DOTFILES:-0}" = "1" ]; then
                echo "Warning: Failed to source .env (check syntax)" >&2
            fi
        fi
    fi
fi
