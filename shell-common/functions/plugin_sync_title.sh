#!/bin/sh
# shell-common/functions/plugin_sync_title.sh
# Build the "chore(claude-plugin): sync manifest" commit title from the
# manifest keys a sync actually changed.
#
# SSOT for the title format shared by the two writers of that commit
# (issue #1558):
#
#   claude/plugin/reconcile.sh  --apply  (full recompute)
#   claude/hooks/plugin-sync.sh          (SessionStart bulk re-sync path)
#
# #1430 gave the single `claude plugin install <x>` commit a "(<target>)"
# suffix so `git log --oneline` could tell one sync from another, but the
# bulk re-sync driven by claude/hooks/plugin-sync-session.sh has no single
# target and kept the bare subject — a commit adding eleven plugins looked
# exactly like one adding none. reconcile.sh already solved that for its
# own commits; keeping the logic here means the two paths cannot drift
# into two different title formats.
#
# Like shell-common/functions/gh_host.sh, this file deliberately has NO
# interactive guard: it only defines functions and produces no output at
# file scope, so the guard would hide the functions from the very callers
# that need them (hooks and one-shot scripts sourcing it non-interactively).
#
# POSIX only — shell-common/functions/*.sh is auto-sourced by both the bash
# and the zsh loader, so no bashisms (no arrays, no `mapfile`, no
# `${*:1:3}`) may appear here.
#
# Requires: jq.

# Advisory only (issue #1454, propagated by #1505): warn once on stderr when
# this file was sourced from a checkout that is a different git repo than
# $HOME/dotfiles. Mandated by shell-common/AGENTS.md for every functions/*.sh
# a non-interactive hook or script sources directly, which is exactly how both
# writers reach this file. Never blocks, and deliberately NOT wrapped in an
# interactive guard — see the header note above; the guard function is itself
# a silent no-op outside the genuine foreign-checkout case. Without it a stale
# sibling checkout would silently supply a different title format, which is
# the one failure this SSOT exists to prevent.
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
    _dotfiles_root_guard_self "$_drg_self" "plugin_sync_title"
else
    printf '[plugin_sync_title] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# Emit the compact JSON in file $1, or the default $2 when that file is
# missing, empty (a 0-byte file makes `jq .` exit 0 with NO output, so a
# plain `jq . || echo` fallback would not fire), or invalid JSON.
_plugin_sync_read_json_or() {
    _psrjo_out=""
    if [ -f "$1" ]; then
        _psrjo_out=$(jq -c '.' "$1" 2>/dev/null)
    fi
    if [ -n "$_psrjo_out" ]; then
        printf '%s' "$_psrjo_out"
    else
        printf '%s' "$2"
    fi
}

# _changed_keys_marketplaces <current_file> <target_json>
#
# Bare "+key"/"-key"/"~key" tokens (added/removed/changed), one per line —
# no explanatory text, unlike reconcile.sh's _diff_marketplaces — for
# embedding in a commit title. <target_json> is a {name: repo} map.
_changed_keys_marketplaces() {
    _ckm_current=$(_plugin_sync_read_json_or "$1" '{}')
    jq -rn --argjson c "$_ckm_current" --argjson t "$2" '
        [ ($t | to_entries[] | select($c[.key] == null) | "+\(.key)"),
          ($c | to_entries[] | select($t[.key] == null) | "-\(.key)"),
          ($t | to_entries[] | select($c[.key] != null and $c[.key] != .value) | "~\(.key)") ]
        | .[]
    '
}

# _changed_keys_plugins <current_file> <target_json>
#
# Same idea for the plugins manifest. <target_json> is a flat array of
# plugin names, so only "+"/"-" are possible (no value to change).
_changed_keys_plugins() {
    _ckp_current=$(_plugin_sync_read_json_or "$1" '{"plugins":[]}')
    jq -rn --argjson c "$_ckp_current" --argjson t "$2" '
        ($c.plugins // []) as $cur |
        [ ($t[]   | select(. as $x | ($cur | index($x)) | not) | "+\(.)"),
          ($cur[] | select(. as $x | ($t   | index($x)) | not) | "-\(.)") ]
        | .[]
    '
}

# _build_sync_title <base> [changed_key...]
#
# Build a commit title naming the changed entries so `git log --oneline`
# distinguishes syncs instead of showing the same subject every time
# (#1430). No items → bare <base>. More than 4 → first 3 + "외 N개" so the
# title never grows unbounded on a large SSOT re-sync.
_build_sync_title() {
    _bst_base="$1"
    shift
    _bst_n="$#"
    if [ "$_bst_n" -eq 0 ]; then
        printf '%s' "$_bst_base"
        return 0
    fi
    if [ "$_bst_n" -le 4 ]; then
        printf '%s (%s)' "$_bst_base" "$*"
        return 0
    fi
    # $1..$3 always exist here — the "-le 4" branch above already returned, so
    # this point is reachable only with 5 or more items. Spelled out positionally
    # rather than as "${*:1:3}" because that slice syntax is a bashism and this
    # file is sourced by POSIX shells too (see the header).
    printf '%s (%s %s %s 외 %d개)' "$_bst_base" "$1" "$2" "$3" "$((_bst_n - 3))"
}

# _plugin_sync_title <base> <mp_file> <mp_target> <pl_file> <pl_target>
#
# The whole title in one call: collect the keys both manifests change, then
# format them. This — not the three primitives above — is what both writers
# actually want, so it is the SSOT boundary; keeping the composition here is
# what stops reconcile.sh and plugin-sync.sh from assembling the same title
# two different ways.
#
# <mp_file>/<pl_file> are the manifests as they still are on disk (call before
# the write); <mp_target>/<pl_target> are the values about to be written.
#
# A jq failure or a malformed manifest yields no keys, which degrades to the
# bare <base> rather than an empty subject.
#
# The newline-separated list from the helpers is split into positional
# params with an explicit `while read` loop rather than unquoted `$var`
# expansion — zsh does not word-split an unquoted parameter by default
# (no SH_WORD_SPLIT), so `_build_sync_title "$base" $changed` silently
# collapsed every key into one malformed argument under zsh while working
# fine under bash/dash (caught by tests/bats/tools/plugin_sync_title_smoke.bats,
# #1558 codex review). The heredoc form runs the loop in the current shell,
# not a subshell, so `set --` below actually sticks.
_plugin_sync_title() {
    _pst_base="$1"
    _pst_changed=$(
        _changed_keys_marketplaces "$2" "$3" 2>/dev/null
        _changed_keys_plugins "$4" "$5" 2>/dev/null
    )
    set --
    while IFS= read -r _pst_line; do
        [ -n "$_pst_line" ] || continue
        set -- "$@" "$_pst_line"
    done <<PST_EOF
$_pst_changed
PST_EOF
    _build_sync_title "$_pst_base" "$@"
}
