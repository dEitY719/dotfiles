#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/mirror_pages_activate.sh
# Wrapper function: delegates to tools/custom/mirror-pages-activate.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

mirror_pages_activate() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/mirror-pages-activate.sh
    "$_exe" "$@"
}

alias mirror-pages-activate='mirror_pages_activate'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func mirror_pages_activate "Activate GHE Pages and rewrite upstream URLs"
