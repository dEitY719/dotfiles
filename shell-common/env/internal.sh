#!/bin/sh
# shell-common/env/internal.sh
# Internal-PC identifiers (GHES host, ...) kept out of this public repo (#1944).
# Real values live in the gitignored internal.local.sh; copy the template:
#   cp shell-common/env/internal.local.example shell-common/env/internal.local.sh
# Public PCs need no file: consumers warn or skip when a variable is unset.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_internal_root="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
if [ -z "${DOTFILES_SKIP_LOCAL_ENV-}" ] && [ -f "$_internal_root/env/internal.local.sh" ]; then
    . "$_internal_root/env/internal.local.sh"
fi
unset _internal_root
