#!/bin/sh
# shell-common/env/proxy.sh
# Proxy configuration (environment-agnostic, POSIX-compatible)
#
# This file provides default proxy settings for public/home environments.
# Environment-specific overrides (corporate proxy, VPN, etc.) are loaded
# from proxy.local.sh if it exists.
#
# Note: Help and diagnostics are in separate files:
#   - functions/proxy_help.sh (help function)
#   - tools/custom/check_proxy.sh (diagnostic tool)

# ============================================================
# DEFAULT PROXY SETTINGS (for public/home environment)
# ============================================================

# No Proxy - Local network exceptions (POSIX-compatible)
export no_proxy="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.local"
export NO_PROXY="$no_proxy"

# HTTP/HTTPS Proxy - Commented out (no proxy by default for public environments)
# Uncomment and configure for corporate proxy environments
# export http_proxy="http://proxy.example.com:8080"
# export https_proxy="http://proxy.example.com:8080"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"

# ============================================================
# ENVIRONMENT-SPECIFIC SETTINGS (loaded if exists)
# ============================================================

# Load environment-specific proxy configuration (if exists)
# This allows overriding default settings for corporate/special environments
#
# Note: When sourcing, $0 may be shell name (bash, -zsh, etc), so we use
# SHELL_COMMON (or DOTFILES_ROOT) for reliable path resolution.
_proxy_root="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
if [ -f "$_proxy_root/env/proxy.local.sh" ]; then
    . "$_proxy_root/env/proxy.local.sh"
fi
unset _proxy_root
