#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/process_utils.sh
# ps-grep — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/psgrep.sh (also ~/.local/bin/ps-grep); this keeps the
# `psgrep` / `ps-grep` names and tab completion in interactive shells.
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

psgrep() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/psgrep.sh "$@"
}

alias ps-grep='psgrep'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func psgrep "Grep the process table"
