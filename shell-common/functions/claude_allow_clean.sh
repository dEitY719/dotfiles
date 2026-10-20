#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/claude_allow_clean.sh
# claude-allow-clean — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/claude_allow_clean.sh (also ~/.local/bin/claude-allow-clean); this keeps the
# `claude_allow_clean` / `claude-allow-clean` names and tab completion in interactive shells.

claude_allow_clean() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/claude_allow_clean.sh "$@"
}

alias claude-allow-clean='claude_allow_clean'
