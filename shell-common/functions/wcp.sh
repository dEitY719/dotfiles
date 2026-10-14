#!/bin/sh
# shell-common/functions/wcp.sh
# wcp — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/wcp.sh (also ~/.local/bin/wcp); this keeps the
# `wcp` / `wcp` names and tab completion in interactive shells.
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

wcp() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/wcp.sh
    "$_exe" "$@"
}

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func wcp "cp that accepts Windows paths (wcp --help)"
