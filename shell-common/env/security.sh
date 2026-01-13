#!/bin/sh
# shell-common/env/security.sh
# Security-related environment variables (POSIX-compatible)
#
# Environment-specific CA certificate setup:
#   1. Copy shell-common/env/security.local.example to security.local.sh
#   2. Choose CA settings for your environment (corporate/home)
#   3. security.local.sh is automatically loaded (.gitignore excludes it)

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

# Load environment-specific settings from security.local.sh (if present).
# NOTE: $0 is unreliable in sourced context, so prefer predefined variables.
_security_root="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
if [ -f "$_security_root/env/security.local.sh" ]; then
    . "$_security_root/env/security.local.sh"
fi
unset _security_root
