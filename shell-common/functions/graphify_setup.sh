#!/bin/sh
# shell-common/functions/graphify_setup.sh
# Wrapper function: delegates to tools/custom/graphify_setup.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

graphify_setup() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/graphify_setup.sh "$@"
}

alias graphify-setup='graphify_setup'
