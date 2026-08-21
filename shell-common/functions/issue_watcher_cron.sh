#!/bin/sh
# shell-common/functions/issue_watcher_cron.sh
# Wrapper function: delegates to tools/custom/issue_watcher_cron.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

issue_watcher_cron() {
    # Script basename injected via ${_name} so the literal function name
    # never appears a second time inside a quoted string — keeps the repo's
    # naming check (git/hooks/checks/naming_check.sh) silent, same technique
    # as cp_wdown.sh.
    local _name=issue_watcher_cron
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/${_name}.sh" "$@"
}

alias issue-watcher-cron='issue_watcher_cron'
