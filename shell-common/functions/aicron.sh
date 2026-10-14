#!/bin/sh
# shell-common/functions/aicron.sh
# Wrapper function: delegates to tools/custom/aicron.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

aicron() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/aicron.sh" "$@"
}

alias ai-cron='aicron'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func aicron "Scheduled AI job manager"
