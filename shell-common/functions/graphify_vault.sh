#!/bin/sh
# shell-common/functions/graphify_vault.sh
# graphify-vault — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/graphify_vault.sh (also ~/.local/bin/graphify-vault); this keeps the
# `graphify_vault` / `graphify-vault` names and tab completion in interactive shells.
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

graphify_vault() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/graphify_vault.sh "$@"
}

alias graphify-vault='graphify_vault'
