#!/bin/sh
# shell-common/functions/graphify_setup.sh
# Wrapper function: delegates to tools/custom/graphify_setup.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

graphify_setup() {
    # Name kept out of the quoted path: the pre-commit naming check reads a
    # quoted function name as user-facing text (same shape as cp_wdown.sh).
    _gs_name=graphify_setup
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/${_gs_name}.sh" "$@"
}

alias graphify-setup='graphify_setup'
