#!/bin/sh
# shell-common/lib/setup/common.sh — shared base of the setup lib (#2137)
#
# Guard-free pure lib (shell-common/AGENTS.md "Guard-free pure lib"): it only
# defines functions and loads other definitions, so non-interactive setup
# scripts can source it without DOTFILES_FORCE_INIT=1. Never auto-sourced —
# every consumer sources it explicitly. POSIX sh.
#
# Bootstrap: sh cannot locate a sourced file, so the caller exports
# SHELL_COMMON (or DOTFILES_ROOT) before sourcing anything under lib/setup/.
#
# Provides
#   _setup_lib_root [candidate]   canonical dotfiles root (pwd -P, main worktree)
#   log_info / log_warning / log_error / log_error_and_exit   ux_* shims
#   plus everything from functions/dotfiles_root.sh, functions/dotfiles_backup.sh
#   and tools/ux_lib/ux_lib.sh (the latter only when not loaded yet).

: "${SHELL_COMMON:=${DOTFILES_ROOT:?export SHELL_COMMON or DOTFILES_ROOT before sourcing lib/setup}/shell-common}"

# shellcheck source=shell-common/functions/dotfiles_root.sh
. "${SHELL_COMMON}/functions/dotfiles_root.sh"
# shellcheck source=shell-common/functions/dotfiles_backup.sh
. "${SHELL_COMMON}/functions/dotfiles_backup.sh"
if ! command -v ux_success >/dev/null 2>&1; then
    # shellcheck source=shell-common/tools/ux_lib/ux_lib.sh
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
fi

# _setup_lib_root [candidate] — physical path of candidate (default: the
# parent of $SHELL_COMMON), canonicalized to the main worktree (#589).
_setup_lib_root() {
    _slr_dir=$(cd -P "${1:-${SHELL_COMMON}/..}" 2>/dev/null && pwd -P) || return 1
    _resolve_dotfiles_root_canonical "$_slr_dir"
}

log_info() { ux_info "$1"; }
log_warning() { ux_warning "$1"; }
log_error() { ux_error "$1"; }
log_error_and_exit() {
    ux_error "$1"
    exit 1
}
