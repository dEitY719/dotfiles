#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/claude_plugin_list.sh
# claude-plugin-list — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/claude_plugin_list.sh (also ~/.local/bin/claude-plugin-list); this keeps the
# `claude_plugin_list` / `claude-plugin-list` names and tab completion in interactive shells.

claude_plugin_list() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/claude_plugin_list.sh "$@"
}

alias claude-plugin-list='claude_plugin_list'
