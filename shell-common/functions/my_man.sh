#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/my_man.sh
# my-man — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/myman.sh (also ~/.local/bin/my-man); this keeps the
# `myman` / `my-man` names and tab completion in interactive shells.

myman() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/myman.sh "$@"
}

alias my-man='myman'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func myman "Friendlier man page viewer"
