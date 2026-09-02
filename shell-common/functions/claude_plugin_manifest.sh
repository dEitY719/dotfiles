#!/bin/sh
# shell-common/functions/claude_plugin_manifest.sh
# SSOT for reading a Claude plugin manifest file into a jq-safe JSON value.
#
# Every writer and reader of claude/plugin/{marketplaces,plugins}.json needs
# the same three-way degradation before it can hand the file to
# `jq --argjson`: a missing file, a 0-byte file and a corrupt file must all
# collapse to a caller-chosen default rather than to the empty string (which
# `--argjson` rejects outright). Four copies of that rule had grown up
# independently (issue #1696):
#
#   claude/plugin/reconcile.sh      _read_json_or            (local function)
#   claude/hooks/plugin-sync.sh     _read_json_or            (local function)
#   claude/plugin/restore.sh        inlined at the call site
#   shell-common/functions/plugin_sync_title.sh
#                                   _plugin_sync_read_json_or
#
# They agreed by accident, not by construction. This file is the one copy the
# rule is now maintained in; all four files above source it and keep only a
# clearly-labelled bootstrap fallback for the half-installed tree they are each
# documented (and, for three of them, tested) to survive — see the comment at
# each fallback.
#
# The list above is the set of copies this file replaced, not every manifest
# read in the tree: claude/hooks/plugin-sync-session.sh reads the same two
# files through filtered jq programs (`keys`, `.mp_keys // []`), which do not
# fit this helper's fixed `jq -c '.'`, and keeps its own reads.
#
# Like shell-common/functions/plugin_sync_title.sh, this file deliberately has
# NO interactive guard: apart from the advisory diagnostics below it defines a
# function and produces no output at file scope, so the guard would hide the
# function from the very callers that need it (hooks and one-shot scripts
# sourcing it non-interactively).
#
# POSIX only — shell-common/functions/*.sh is auto-sourced by both the bash
# and the zsh loader, so no bashisms (no arrays, no `local`, no `[[ ]]`) may
# appear here.
#
# Requires: jq.

# Include-once sentinel (issue #1505, same rationale as dotfiles_root.sh): this
# file is reached twice per interactive shell — once by the functions/ auto-
# loader's own pass over shell-common/functions/*.sh, then again when that pass
# reaches plugin_sync_title.sh, which sources this file itself. Repeats re-parse
# the file, redefine the function and re-run the guard below (a `dirname` fork
# plus an un-memoized `git rev-parse` subshell each time — dotfiles_root.sh
# memoizes only the canonical side) for no benefit. `return` (not `exit`) since
# this only ever runs as a sourced dot-script; the `|| exit 0` fallback covers
# the (unsupported) case of running it directly.
if [ -n "${_CLAUDE_PLUGIN_MANIFEST_SH_SOURCED-}" ]; then
    # shellcheck disable=SC2317  # exit fallback only runs if this file is
    # executed directly (not sourced), so `return` succeeding makes it look
    # unreachable to static analysis.
    return 0 2>/dev/null || exit 0
fi
_CLAUDE_PLUGIN_MANIFEST_SH_SOURCED=1

# Advisory only (issue #1454, propagated by #1505): warn once on stderr when
# this file was sourced from a checkout that is a different git repo than
# $HOME/dotfiles. This is the standard guard that
# docs/guide/playbooks/shell-common-cheatsheet.md → "Foreign-Checkout Guard
# Snippet" requires be copied character-for-character (only the LABEL differs)
# into each guarded shell-common/functions/*.sh. It speaks on the loader
# auto-source path (shell-common/util/safe_source.sh treats */functions/* as
# "important" and does not redirect its stderr); the four explicit callers all
# source with `2>/dev/null`, so it is deliberately silent there. Never blocks,
# and deliberately NOT wrapped in an interactive guard — see the header note
# above; the guard function is itself a silent no-op outside the genuine
# foreign-checkout case. Without it a stale sibling checkout could silently
# supply different manifest-read semantics than the manifest writers assume.
#
# The self-path branch must stay here at file top level — zsh rebinds $0 to
# the sourced file (FUNCTION_ARGZERO) only for this file's own statements,
# and inside a function $0 is the function's own name. This file is real
# POSIX sh, so the bash array form is reached only when $BASH_VERSION proves
# bash: dash aborts with "Bad substitution" the moment it expands
# ${BASH_SOURCE[0]}.
if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    # shellcheck disable=SC3028  # bash-only var, gated by $BASH_VERSION above
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "claude_plugin_manifest"
else
    printf '[claude_plugin_manifest] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# _claude_plugin_read_json_or <file> <default>
#
# Emit the compact JSON in <file>, or <default> when that file is missing,
# empty (a 0-byte file makes `jq .` exit 0 with NO output, so a plain
# `jq . || echo` fallback would not fire), or invalid JSON.
#
# No trailing newline: every caller feeds the result straight into
# `jq --argjson`, and the `if/else` form (rather than `[ -n ] && ... || ...`)
# keeps the default branch reachable even if the success `printf` ever fails.
_claude_plugin_read_json_or() {
    _cprjo_out=""
    if [ -f "$1" ]; then
        _cprjo_out=$(jq -c '.' "$1" 2>/dev/null)
    fi
    if [ -n "$_cprjo_out" ]; then
        printf '%s' "$_cprjo_out"
    else
        printf '%s' "$2"
    fi
}

# _claude_plugin_tombstone_prune <tombstone-json> <installed-plugins-json> <installed-marketplaces-json>
#
# Drop from a tombstone every entry the SSOT says is installed again, and emit
# the pruned tombstone as compact JSON. Reinstalling has to cancel a tombstone
# or the reinstall silently does not stick — claude/plugin/restore.sh subtracts
# tombstones from its restore union, so a stale one keeps uninstalling the
# plugin the user just asked for.
#
# Two writers need this identical subtraction (PR #1695 agy FOLLOW-UP):
# claude/hooks/plugin-sync.sh's add branch (the event path) and
# claude/plugin/reconcile.sh --apply (the full-recompute path that covers
# events the hook missed). Keeping one copy is what stops them drifting into
# two different notions of "installed again".
#
# Emits nothing on a jq failure, so a caller can tell "prune produced no
# change" (unchanged JSON) from "prune failed" (empty) and skip the write.
_claude_plugin_tombstone_prune() {
    jq -cn --argjson old "$1" --argjson pl "$2" --argjson mp "$3" \
        '{marketplaces: (($old.marketplaces // []) - $mp),
          plugins:      (($old.plugins // []) - $pl)}' 2>/dev/null
}
