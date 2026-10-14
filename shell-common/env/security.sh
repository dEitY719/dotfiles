#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/env/security.sh
# Security-related environment variables (POSIX-compatible)
#
# Environment-specific CA certificate setup:
#   1. Copy shell-common/env/security.local.example to security.local.sh
#   2. Choose CA settings for your environment (corporate/home)
#   3. That file is automatically loaded (.gitignore excludes it)

# SSH agent socket configuration

if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    # Prevent double slashes: ${var%/} removes trailing slash
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR%/}/ssh-agent.socket"
else
    # Fallback (systemd runtime directory convention)
    uid="$(id -u)"
    export SSH_AUTH_SOCK="/run/user/${uid}/ssh-agent.socket"
fi

# GPG TTY configuration (only when TTY is available)
if tty >/dev/null 2>&1; then
    GPG_TTY="$(tty)"
    export GPG_TTY
fi

# ========================================
# Environment-specific security settings (CA certificates, etc.)
# ========================================

# Load environment-specific settings (if present).
# NOTE: $0 is unreliable in sourced context, so prefer predefined variables.
_local_env_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/util/local_env.sh"
[ -r "$_local_env_lib" ] && . "$_local_env_lib" && _dotfiles_source_local security
unset _local_env_lib
