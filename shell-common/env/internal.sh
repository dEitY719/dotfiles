#!/bin/sh
# shell-common/env/internal.sh
# Internal-PC identifiers (GHES host, ...) kept out of this public repo (#1944).
# Real values live in a gitignored local file; copy the template:
#   cp shell-common/env/internal.local.example shell-common/env/internal.local.sh
# Public PCs need no file: consumers warn or skip when a variable is unset.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_local_env_lib="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/util/local_env.sh"
[ -r "$_local_env_lib" ] && . "$_local_env_lib" && _dotfiles_source_local internal
unset _local_env_lib
