#!/bin/sh
# shell-common/functions/aicron.sh
# Wrapper function: delegates to tools/custom/aicron.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

aicron() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/aicron.sh" "$@"
}

alias ai-cron='aicron'
