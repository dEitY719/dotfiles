#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/claude_marketplace_autoupdate.sh
# claude-marketplace-autoupdate — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/claude_marketplace_autoupdate.sh (also ~/.local/bin/claude-marketplace-autoupdate); this keeps the
# `claude_marketplace_autoupdate` / `claude-marketplace-autoupdate` names and tab completion in interactive shells.

claude_marketplace_autoupdate() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/claude_marketplace_autoupdate.sh "$@"
}

alias claude-marketplace-autoupdate='claude_marketplace_autoupdate'
