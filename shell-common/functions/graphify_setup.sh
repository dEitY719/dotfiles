#!/bin/sh
# shell-common/functions/graphify_setup.sh
# Wrapper function: delegates to tools/custom/graphify_setup.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

graphify_setup() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/graphify_setup.sh
    "$_exe" "$@"
}

alias graphify-setup='graphify_setup'
