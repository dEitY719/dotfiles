#!/bin/sh
# shell-common/util/bootstrap.sh
# Shared prelude for bash/main.bash and zsh/main.zsh (#2134).
#
# Usage (from an entry point, after the inline MERGE_HEAD diagnostic):
#   DOTFILES_ROOT=<candidate root>
#   . "${DOTFILES_ROOT}/shell-common/util/bootstrap.sh"   # then branch on $?
#   dotfiles_load_all
#
# Status: 0 = loaded, 1 = skip (conditions below), 2 = a core file failed to
# source. The entry point returns quietly on 1 and reports 2. No standard interactive guard line here on purpose:
# dotfiles_should_skip_init IS the guard, and it must reach the caller as a
# status rather than a silent `return 0` that would let the caller continue.

# Codex CLI environment (npm managed or explicit CLI flag). Loading dotfiles
# there causes permission errors and timeouts, whatever the shell.
is_codex_env() {
    [ -n "${CODEX_CLI-}" ] ||
        [ -n "${CODEX_MANAGED_BY_NPM-}" ] ||
        [ -n "${CODEX_SANDBOX_NETWORK_DISABLED-}" ]
}

# Returns 0 (skip initialization) for a non-interactive shell, an explicit
# DOTFILES_SKIP_INIT, or a Codex environment; DOTFILES_FORCE_INIT wins over all.
dotfiles_should_skip_init() {
    [ -n "${DOTFILES_FORCE_INIT-}" ] && return 1
    case $- in *i*) ;; *) return 0 ;; esac
    [ -n "${DOTFILES_SKIP_INIT-}" ] && return 0
    is_codex_env && return 0
    return 1
}

dotfiles_should_skip_init && return 1

# The loading core comes from the same tree as this bootstrap.sh (the entry
# point's candidate root): canonicalizing first would pair a linked worktree's
# entry point with the main checkout's possibly older loader.sh.
_dotfiles_core="${DOTFILES_ROOT}/shell-common/util"

# Canonicalize to the main worktree (issue #589). When sourced inside a linked
# worktree, DOTFILES_ROOT would otherwise point at the worktree path and bleed
# into ~/.claude-*/ symlinks created by claude_accounts_init. The helper is
# source-from-candidate-path safe.
if [ -r "${DOTFILES_ROOT}/shell-common/lib/dotfiles_root.sh" ]; then
    . "${DOTFILES_ROOT}/shell-common/lib/dotfiles_root.sh"
    _dotfiles_root_canonicalize
fi
export DOTFILES_ROOT

SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
export SHELL_COMMON

# Counter of files sourced through safe_source (shown by dotfiles_init_summary).
SOURCED_FILES_COUNT=0

. "${_dotfiles_core}/safe_source.sh" || return 2
# UX library first: everything loaded after it may call ux_* functions.
. "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" || return 2
. "${_dotfiles_core}/loader.sh" || return 2
unset _dotfiles_core
return 0
