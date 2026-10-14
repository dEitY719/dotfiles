#!/bin/sh
# shell-common/functions/git_ssh_check.sh
# git-ssh-check — thin wrapper (#2195). The logic is the PATH executable
# tools/custom/git_ssh_check.sh (also ~/.local/bin/git-ssh-check); this keeps the
# `git_ssh_check` / `git-ssh-check` names and tab completion in interactive shells.
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

git_ssh_check() {
    local _exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/git_ssh_check.sh
    "$_exe" "$@"
}

# Alias for dash format
alias git-ssh-check='git_ssh_check'
