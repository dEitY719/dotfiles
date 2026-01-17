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
        if command -v ux_warning >/dev/null 2>&1; then
            ux_warning ".env가 아직 암호화된 상태입니다 (git-crypt locked). 먼저 실행: git-crypt unlock"
        else
            echo "Warning: .env가 아직 암호화된 상태입니다 (git-crypt locked). 먼저 실행: git-crypt unlock" >&2
        fi
    else
        # shellcheck source=/dev/null
        . "$env_file"
    fi
fi
