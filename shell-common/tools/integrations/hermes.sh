#!/bin/sh
# shell-common/tools/integrations/hermes.sh
# Hermes Agent convenience aliases
#
# Deliberately minimal: the upstream installer puts a self-contained `hermes`
# binary on PATH itself, so there is nothing here to export or wrap. Config is
# owned by hermes/setup.sh (symlinks ~/.hermes/config.yaml into this repo).
#
# Setup:   ./hermes/setup.sh
# Details: hermes-help

# ========================================
# Load UX Library
# ========================================

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

if ! type ux_header >/dev/null 2>&1; then
    _hermes_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_hermes_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _hermes_dir
fi

# ========================================
# Hermes Aliases
# ========================================
alias hermes-doctor='hermes doctor'
alias hermes-config='hermes config'
