#!/bin/sh
# shell-common/functions/cp_wdown.sh
# Thin POSIX wrapper around shell-common/tools/custom/cp_wdown.sh.
#
# The bash-only implementation lives in tools/custom/ (NOT auto-sourced); since
# #2195 it is also a PATH executable (~/.local/bin/cp-wdown). This wrapper keeps
# the `cp_wdown` function for bash and zsh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

cp_wdown() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/cp_wdown.sh
    "$_exe" "$@"
}
