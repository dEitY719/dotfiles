#!/bin/sh
# shell-common/functions/dotfiles_root.sh
#
# Canonicalize $DOTFILES_ROOT so it always resolves to the MAIN git worktree,
# never a linked worktree. Issue #589.
#
# Why: claude/setup.sh and claude_accounts_init evaluate ${DOTFILES_ROOT} at
# call time and embed that literal path into ~/.claude-*/{settings.json,
# statusline-command.sh, skills, docs, ...} symlinks. If setup.sh is invoked
# from a linked worktree, those symlinks point at the worktree path. When
# the worktree is removed later, the symlinks dangle → Claude Code silently
# falls back to default settings (no statusline, no hooks, no plugins). The
# user sees "왜 안 되지" with no error message.
#
# Strategy: when called inside a linked worktree, walk back to the main
# worktree via `git rev-parse --git-common-dir`. Pure POSIX, no bash-isms.

# Sourced both by interactive shells (loaders) and by non-interactive
# setup.sh runs. The interactive guard pattern is intentionally absent so
# setup.sh can rely on the function being defined even without
# DOTFILES_FORCE_INIT — there is no observable output until the function
# is invoked.

# _resolve_dotfiles_root_canonical CANDIDATE
#
# Echo the canonical (main-worktree) directory that should be used as
# $DOTFILES_ROOT, given CANDIDATE as the script-derived starting point.
#
# Behavior:
#   - CANDIDATE empty/missing → echo "$CANDIDATE" (no-op).
#   - DOTFILES_ROOT_NO_CANONICALIZE=1 in env → echo "$CANDIDATE" (escape
#     hatch for users intentionally testing a worktree's dotfiles).
#   - git unavailable → echo "$CANDIDATE" (minimal hosts).
#   - CANDIDATE is not a git worktree → echo "$CANDIDATE".
#   - CANDIDATE is the MAIN worktree → echo "$CANDIDATE".
#   - CANDIDATE is a linked worktree → echo the resolved main worktree path.
#
# Always returns 0 — a probing failure must fall back to CANDIDATE so this
# helper can never break a shell that was working before.
_resolve_dotfiles_root_canonical() {
    _rdrc_candidate="${1:-}"

    if [ -z "$_rdrc_candidate" ]; then
        echo ""
        return 0
    fi

    if [ ! -d "$_rdrc_candidate" ]; then
        echo "$_rdrc_candidate"
        return 0
    fi

    if [ "${DOTFILES_ROOT_NO_CANONICALIZE:-0}" = "1" ]; then
        echo "$_rdrc_candidate"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "$_rdrc_candidate"
        return 0
    fi

    _rdrc_common=$(git -C "$_rdrc_candidate" rev-parse --git-common-dir 2>/dev/null) || {
        echo "$_rdrc_candidate"
        return 0
    }

    if [ -z "$_rdrc_common" ]; then
        echo "$_rdrc_candidate"
        return 0
    fi

    case "$_rdrc_common" in
        /*) ;;
        *) _rdrc_common="$_rdrc_candidate/$_rdrc_common" ;;
    esac

    _rdrc_main=$(dirname "$_rdrc_common" 2>/dev/null)
    if [ -z "$_rdrc_main" ] || [ ! -d "$_rdrc_main" ]; then
        echo "$_rdrc_candidate"
        return 0
    fi

    _rdrc_main=$(cd "$_rdrc_main" 2>/dev/null && pwd) || {
        echo "$_rdrc_candidate"
        return 0
    }

    echo "$_rdrc_main"
}

# _dotfiles_root_canonicalize
#
# In-place: re-export $DOTFILES_ROOT (and $SHELL_COMMON) from a worktree
# path to the canonical main-worktree path. No-op if already canonical or
# if DOTFILES_ROOT is unset. Always returns 0 — a downgrade-safe wrapper
# loaders can call unconditionally.
_dotfiles_root_canonicalize() {
    [ -n "${DOTFILES_ROOT:-}" ] || return 0
    _drc_resolved=$(_resolve_dotfiles_root_canonical "$DOTFILES_ROOT")
    if [ -n "$_drc_resolved" ] && [ "$_drc_resolved" != "$DOTFILES_ROOT" ]; then
        DOTFILES_ROOT="$_drc_resolved"
        export DOTFILES_ROOT
        SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
        export SHELL_COMMON
    fi
    return 0
}
