#!/bin/sh
# shell-common/functions/issue_watcher_cron.sh
# Wrapper function: delegates to tools/custom/issue_watcher_cron.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

issue_watcher_cron() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Script basename injected via ${_name} so the literal function name
    # never appears a second time inside a quoted string — keeps the repo's
    # naming check (git/hooks/checks/naming_check.sh) silent, same technique
    # as cp_wdown.sh.
    local _name=issue_watcher_cron
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/${_name}.sh" "$@"
}

alias issue-watcher-cron='issue_watcher_cron'

# Help topic: delegates to the tool's own --help (the usage SSOT). Also keeps
# `my-help issue-watcher-cron` from falling through to running a real tick.
issue_watcher_cron_help() {
    issue_watcher_cron --help
}

alias issue-watcher-cron-help='issue_watcher_cron_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help issue_watcher_cron_help "[Development] issue-watcher cron tick (assigned issues -> /gh-flow:issue)" development
