#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/mirror_pages_activate.sh
# Wrapper function: delegates to tools/custom/mirror-pages-activate.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

mirror_pages_activate() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        mirror_pages_activate_help
        return 0
    fi
    "${SHELL_COMMON}/tools/custom/mirror-pages-activate.sh" "$@"
}

alias mirror-pages-activate='mirror_pages_activate'
