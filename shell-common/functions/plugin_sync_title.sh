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
    # First three, space-joined. Written as a loop rather than "${*:1:3}"
    # because that slice syntax is a bashism and this file is sourced by
    # POSIX shells too (see the header).
    _bst_head=""
    _bst_i=0
    for _bst_k in "$@"; do
        _bst_i=$((_bst_i + 1))
        if [ "$_bst_i" -gt 3 ]; then
            break
        fi
        if [ -z "$_bst_head" ]; then
            _bst_head="$_bst_k"
        else
            _bst_head="$_bst_head $_bst_k"
        fi
    done
    printf '%s (%s 외 %d개)' "$_bst_base" "$_bst_head" "$((_bst_n - 3))"
}
