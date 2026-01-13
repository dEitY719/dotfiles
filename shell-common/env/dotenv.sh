#!/bin/sh
# shell-common/env/dotenv.sh
# Load environment variables from .env file if it exists
# POSIX-compatible - sourced automatically by bash and zsh

# Determine the dotfiles root directory
if [ -z "${DOTFILES_ROOT}" ]; then
    DOTFILES_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

# Source .env file if it exists
if [ -f "${DOTFILES_ROOT}/.env" ]; then
    # Use sh -c to avoid subshell issues when sourcing
    . "${DOTFILES_ROOT}/.env"
fi
