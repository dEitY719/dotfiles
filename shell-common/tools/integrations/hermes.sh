#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/tools/integrations/hermes.sh
# Hermes Agent convenience aliases + internal-GHES skill install wrapper
#
# Deliberately minimal: the upstream installer puts a self-contained `hermes`
# binary on PATH itself, so nothing is exported here. The only wrapper is
# hermes_skill_install, which adds per-command env for skill URLs on the
# internal GHES. Config is owned by hermes/setup.sh (copies
# ~/.hermes/config.yaml from this repo once).
#
# Setup:   ./hermes/setup.sh
# Details: hermes-help

# ========================================
# Hermes Aliases
# ========================================
alias hermes-doctor='hermes doctor'
alias hermes-config='hermes config'
alias hermes-skill-install='hermes_skill_install'

# ========================================
# Skill install from the internal GHES
# ========================================
# `hermes skills install <url> ...` passthrough. When the first http(s) arg's
# host equals $DOTFILES_GHES_HOST (internal.local.sh), that one call gets:
#   HERMES_ALLOW_PRIVATE_URLS=1  - SSRF guard is_safe_url() blocks RFC1918 IPs
#   SSL_CERT_FILE=<system bundle> - WSL default points at a single proxy CA
# Per-command env only: never exported, config.yaml never touched.
# The SSRF bypass covers the whole call, redirects included — only feed it
# URLs from the GHES you trust.
hermes_skill_install() {
    local _hsi_arg _hsi_host="" _hsi_bundle _hsi_ghes
    for _hsi_arg in "$@"; do
        case "$_hsi_arg" in
        http://* | https://*)
            _hsi_host=${_hsi_arg#*://}
            _hsi_host=${_hsi_host%%/*}
            _hsi_host=${_hsi_host##*@}
            _hsi_host=${_hsi_host%%:*}
            break
            ;;
        esac
    done

    # DNS names are case-insensitive.
    _hsi_host=$(printf '%s' "$_hsi_host" | tr '[:upper:]' '[:lower:]')
    _hsi_ghes=$(printf '%s' "${DOTFILES_GHES_HOST-}" | tr '[:upper:]' '[:lower:]')
    if [ -z "$_hsi_ghes" ] || [ "$_hsi_host" != "$_hsi_ghes" ]; then
        command hermes skills install "$@"
        return
    fi

    _hsi_bundle=${HERMES_SKILL_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}
    if [ ! -f "$_hsi_bundle" ]; then
        ux_error "CA bundle not found: $_hsi_bundle (set HERMES_SKILL_CA_BUNDLE)"
        return 1
    fi
    HERMES_ALLOW_PRIVATE_URLS=1 SSL_CERT_FILE="$_hsi_bundle" command hermes skills install "$@"
}
