#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/wsl_check.sh
# wsl-check — thin wrapper (#2155). The logic is the PATH executable
# tools/custom/wsl_check.sh (also ~/.local/bin/wsl-check); this keeps the
# `wsl_check` / `wsl-check` names and tab completion in interactive shells.

wsl_check() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/wsl_check.sh "$@"
}

alias wsl-check='wsl_check'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func wsl_check "WSL and Docker environment health check"
