#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/functions/devx.sh
# Dev helper — Type 2A positional dispatcher (issue #726 / #722 PR 2).
# Thin wrapper (#2195): the logic is the PATH executable
# shell-common/tools/custom/devx.sh (~/.local/bin/devx).
#
# Routes sub-commands to `mise run <task>` for lint/fix and to in-process
# helpers for repo-internal checks (lint-helpfunc / lint-deadcode / stat).
# Replaces tools/dev.sh, absorbing its full sub-command surface. Unknown
# sub-commands fail fast (no passthrough) per command-design-pattern.md §6.
#
# Help lives in devx_help.sh (no `devx-help` alias — see §7.6.1 deviation
# documented in devx_help.sh and PR body for #726).

devx() {
    "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/devx.sh "$@"
}

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func devx "Dev helper — mise wrapper and repo checks"
