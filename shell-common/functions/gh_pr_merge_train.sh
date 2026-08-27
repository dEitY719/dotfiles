#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_merge_train.sh
# SSOT for the merge-train target filter (issue #1524).
#
# Background (issue #1524, bug B):
# The filter that decides which of your open PRs the merge train may touch used
# to exist twice — once as real `jq` inside
# `shell-common/tools/custom/pr_merge_train_cron.sh` (`_pmt_target_count`), and
# once as English prose inside `claude/skills/gh-pr-merge-train/SKILL.md`
# ("drop every PR updated within the last 11 minutes and every draft"). Prose is
# executed by an LLM, which can skip it, mis-add the minutes, or read a stale
# clock — and when it does, the train merges a PR whose deferred review-reply
# pass has not landed yet. Both call sites now call the one function below, so
# there is exactly one implementation and one place the number 11 lives.
#
# Usage:
#   _gh_pr_merge_train_quiet_minutes
#   _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]
#   <one gh-pr-view JSON object> | _gh_pr_merge_train_has_reply_pending_label
#
# `_gh_pr_merge_train_quiet_minutes`
#   Echo the quiet period in minutes. Default 11; override with the env var
#   GH_PR_MERGE_TRAIN_QUIET_MINUTES. This is the ONE place the number is
#   hardcoded — the cron dispatcher's usage text and
#   `claude/skills/gh-pr-merge-train/references/ordering.md` both cite it.
#   11 = the 4-minute `--defer-reply` window `gh:issue-flow` Step 2.4 schedules
#   + the reply pass's own runtime + slack (D-6).
#
# `_gh_pr_merge_train_filter_targets`
#   Read a JSON array on stdin — the shape `gh pr list --json ...` answers with
#   — and echo the same array on stdout with every non-target element removed.
#   A surviving element is passed through UNCHANGED, every field included: the
#   dispatcher only reads `number`/`updatedAt`/`isDraft`, but the skill also
#   needs `mergeable`/`mergeStateStatus`/`baseRefName`/`title` for the D-2 sort
#   and the D-1 routing table, so this function must never project fields away.
#
#   An element is DROPPED when any of these holds:
#     1. `.isDraft` is true               — DRAFT is a skip row in the D-1 table.
#     2. `.labels[].name` has `reply-pending`
#                                         — a deferred `gh:pr-reply` pass is
#                                           still outstanding (see below).
#     3. `.updatedAt` is newer than `--now` minus the quiet period, OR cannot be
#        read at all (missing / null / unparseable). The unreadable case fails
#        *closed* on purpose: `// empty` (not `// 0`) makes the `select` drop
#        the element, because `// 0` would become epoch zero — `<= $cutoff` for
#        any clock — and count an unreadable PR as a target, the exact direction
#        D-6 exists to prevent.
#
#   Flags:
#     --now <epoch-seconds>  REQUIRED. The caller supplies the clock reading, so
#                            this function stays pure and deterministic and the
#                            bats suite can test it without mocking `date`.
#     --minutes <n>          Override the quiet period for this call; defaults
#                            to `_gh_pr_merge_train_quiet_minutes`.
#
#   Return codes:
#     0 — filtered array on stdout (possibly `[]`).
#     1 — usage error, or stdin was empty / not parsable JSON. Nothing on
#         stdout. This is a secondary defense only: the dispatcher already ends
#         the tick when `gh pr list` itself fails, and the skill ends the run.
#
# The `reply-pending` label (issue #1524, bug A):
# The quiet period is a *time-based proxy* for "has the deferred review-reply
# pass finished", and time is a bad proxy — a slow reply pass outlives the
# window and the train merges anyway. The label is the real signal, and its
# name is a fixed literal shared by three call sites:
#   - this file      drops any PR carrying it (hard skip, regardless of timing)
#   - devx:pr-review-all  ADDS it on the `defer` branch (Step 5)
#   - gh:pr-reply         REMOVES it when the reply pass completes (Step 6)
# The quiet period stays as the BACKSTOP: PRs opened by hand or by another tool
# never get the label, and a session that died mid-pass never removes it.
#
# `_gh_pr_merge_train_has_reply_pending_label`
#   The same "does `.labels[]` contain `reply-pending`" question, asked of ONE
#   PR object (not an array) on stdin. `_gh_pr_merge_train_filter_targets`
#   above answers it for the whole queue at Step 2; `references/routing-table.md`
#   F-3 asks it again per PR, right before acting, because a label can be
#   *added mid-run* (a deferred devx:pr-review-all pass) after Step 2 already
#   built the queue. Both call sites run this one function so the predicate
#   itself cannot drift apart the way the quiet-minutes number used to (#1524).
#
# NOTE: This file intentionally has NO interactive guard. It is a pure
# function-defining library (no top-level side effects) sourced from two
# non-interactive contexts: the `pr_merge_train_cron.sh` cron dispatcher, and
# the `gh:pr-merge-train` skill's Bash tool calls (Claude Code runs those as
# `bash --noprofile --norc`). An interactive guard would `return 0` before
# defining either function, breaking both with `command not found` — the same
# reason the NOTE exists in gh_pr_edit_safe.sh and gh_project_status.sh
# (PR #497 / issue #720).

# D-6 quiet period, in minutes. The one hardcoded 11 in the repo.
_gh_pr_merge_train_quiet_minutes() {
    local _m="${GH_PR_MERGE_TRAIN_QUIET_MINUTES:-11}"
    case "$_m" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] GH_PR_MERGE_TRAIN_QUIET_MINUTES=%s is not a number — using 11\n' \
                "$_m" >&2
            _m=11
            ;;
    esac
    printf '%s\n' "$_m"
}

_gh_pr_merge_train_filter_targets() {
    local _now="" _minutes="" _cutoff _json _out

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --now)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --now requires an argument\n' >&2
                    return 1
                fi
                _now="$2"
                shift 2
                ;;
            --minutes)
                if [ -z "${2-}" ]; then
                    printf '[gh-pr-merge-train] --minutes requires an argument\n' >&2
                    return 1
                fi
                _minutes="$2"
                shift 2
                ;;
            *)
                printf '[gh-pr-merge-train] unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    # --now is required rather than defaulted to `date +%s`: a caller that
    # cannot read the clock must decide what that means for itself (the cron
    # dispatcher ends the tick), and a default would quietly paper over it.
    case "$_now" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] usage: _gh_pr_merge_train_filter_targets --now <epoch-seconds> [--minutes <n>]\n' >&2
            return 1
            ;;
    esac

    if [ -z "$_minutes" ]; then
        _minutes=$(_gh_pr_merge_train_quiet_minutes)
    fi
    case "$_minutes" in
        '' | *[!0-9]*)
            printf '[gh-pr-merge-train] --minutes must be a non-negative integer: %s\n' "$_minutes" >&2
            return 1
            ;;
    esac

    _cutoff=$((_now - _minutes * 60))

    _json=$(cat)
    [ -n "$_json" ] || return 1

    # `.labels[]?.name` covers both shapes `gh` answers with: the objects
    # `--json labels` returns, and an absent `labels` key (the dispatcher used
    # to omit the field entirely) — `[]?` on a missing key yields nothing, so a
    # PR list without labels simply never matches.
    _out=$(printf '%s' "$_json" | jq --argjson cutoff "$_cutoff" '
        [ .[]?
          | select((.isDraft // false) | not)
          | select([ .labels[]?.name? ] | index("reply-pending") | not)
          | select(((.updatedAt // "") | fromdateiso8601? // empty) <= $cutoff)
        ]
    ' 2>/dev/null) || return 1
    [ -n "$_out" ] || return 1

    printf '%s\n' "$_out"
}

# Read one PR object (the shape `gh pr view --json labels,...` answers with,
# not an array) on stdin. 0 = it carries the `reply-pending` label, 1 =
# it does not (including malformed / missing `labels`). See the header note
# above for why this exists alongside `_gh_pr_merge_train_filter_targets`
# instead of routing-table.md re-deriving the same jq expression by hand.
_gh_pr_merge_train_has_reply_pending_label() {
    jq -e '[ .labels[]?.name? ] | index("reply-pending")' >/dev/null 2>&1
}

# Self-check (issue #724): catch silent breakage where this file sources
# cleanly but its public functions never get defined — an interactive-guard
# regression, a syntax error mid-file, a future rename. Both call sites treat a
# missing function as a hard failure (the dispatcher ends the tick), but the
# warning is what names the cause. rc stays 0 — sourcing must not fail.
for _gh_pmt_selfcheck_fn in \
    _gh_pr_merge_train_quiet_minutes \
    _gh_pr_merge_train_filter_targets \
    _gh_pr_merge_train_has_reply_pending_label; do
    command -v "$_gh_pmt_selfcheck_fn" >/dev/null 2>&1 && continue
    printf '[gh_pr_merge_train] BUG: %s undefined after source — the merge-train target filter will not run. See dotfiles #724 / #1524.\n' \
        "$_gh_pmt_selfcheck_fn" >&2
done
unset _gh_pmt_selfcheck_fn
:
