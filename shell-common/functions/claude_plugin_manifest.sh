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
# rule is now maintained in; the three scripts above source it and keep only a
# clearly-labelled bootstrap fallback for the half-installed tree they are each
# documented (and, for two of them, tested) to survive — see the comment at
# each fallback.
#
# Like shell-common/functions/plugin_sync_title.sh, this file deliberately has
# NO interactive guard: it only defines a function and produces no output at
# file scope, so the guard would hide the function from the very callers that
# need it (hooks and one-shot scripts sourcing it non-interactively).
#
# POSIX only — shell-common/functions/*.sh is auto-sourced by both the bash
# and the zsh loader, so no bashisms (no arrays, no `local`, no `[[ ]]`) may
# appear here.
#
# Requires: jq.

# Advisory only (issue #1454, propagated by #1505): warn once on stderr when
# this file was sourced from a checkout that is a different git repo than
# $HOME/dotfiles. Mandated by shell-common/AGENTS.md for every functions/*.sh
# a non-interactive hook or script sources directly, which is exactly how all
# three callers reach this file. Never blocks, and deliberately NOT wrapped in
# an interactive guard — see the header note above; the guard function is
# itself a silent no-op outside the genuine foreign-checkout case. Without it a
# stale sibling checkout could silently supply different manifest-read
# semantics than the manifest writers assume.
#
# The self-path branch must stay here at file top level — zsh rebinds $0 to
# the sourced file (FUNCTION_ARGZERO) only for this file's own statements,
# and inside a function $0 is the function's own name. This file is real
# POSIX sh, so the bash array form is reached only when $BASH_VERSION proves
# bash: dash aborts with "Bad substitution" the moment it expands
# ${BASH_SOURCE[0]}.
if [ -n "${ZSH_VERSION-}" ]; then
    _cpm_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    # shellcheck disable=SC3028  # bash-only var, gated by $BASH_VERSION above
    _cpm_self="${BASH_SOURCE[0]-}"
else
    _cpm_self=""
fi
_cpm_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_cpm_helper" ]; then
    . "$_cpm_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_cpm_self" "claude_plugin_manifest"
else
    printf '[claude_plugin_manifest] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_cpm_helper" >&2
fi
unset _cpm_self _cpm_helper

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
