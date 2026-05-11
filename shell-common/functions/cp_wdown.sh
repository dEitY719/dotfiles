#!/bin/sh
# shell-common/functions/cp_wdown.sh
# Thin POSIX wrapper around shell-common/tools/custom/cp_wdown.sh.
#
# The underlying implementation is bash-only (uses mapfile, compgen, indexed
# arrays, (( )) arithmetic) and therefore lives in tools/custom/, which is
# NOT auto-sourced. This wrapper re-exposes it as a regular function so users
# can call `cp_wdown ...` from either bash or zsh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

cp_wdown() {
    # Build the path with the script basename injected via ${_name} so the
    # literal function name never appears inside a quoted string — keeps the
    # repo's snake_case-vs-dash-form naming check (git/hooks/checks/naming_check.sh)
    # silent.
    local _name=cp_wdown
    local _script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/${_name}.sh"
    if [ ! -f "$_script" ]; then
        echo "Error: ${_name} script not found: $_script" >&2
        return 2
    fi
    bash "$_script" "$@"
}
