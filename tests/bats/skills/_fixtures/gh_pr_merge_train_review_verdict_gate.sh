#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_train_review_verdict_gate.sh
# Source-of-truth mirror for the review verdict gate documented in
#   claude/skills/gh-pr-merge-train/references/review-verdict-gate.md
#   claude/skills/gh-pr-merge-train/references/routing-table.md  (F-3 re-check)
#
# Issue #1564 (umbrella #1527): reviewer verdicts reached the PR as comment
# text and nothing machine-readable, so PR #1518 merged 32 minutes after two
# independent blocking reviews. #1562 fixed the parser, #1563 fixed the label
# lifecycle, and this is the consumer: two labels, one table, no comment
# parsing anywhere in the train.
#
# Unlike the approval-gate fixture beside it, this one does NOT re-implement
# the predicates — it sources the real `gh_pr_merge_train.sh` and calls
# `_gh_pr_merge_train_has_review_{blocked,passed}_label`. That is the point of
# #1524's shared-function rule: a mirror that re-derived the jq could pass
# while the shipped predicate drifted.
#
# Keep the ORDER and the reason strings in sync with the doc. If a row changes,
# mirror it here so the bats suite catches the drift.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_merge_train.sh"

# Mirrors review-verdict-gate.md -> "The decision table".
# One PR object (the `gh pr list --json ...,labels` element shape) as $1.
# Echoes `proceed` or `skip:<reason>`.
#
# review-blocked is tested FIRST so it wins over a stale review-passed. The
# absence branch is the `elif`, which is what makes "no label" a skip rather
# than a pass — the invariant the whole issue is about.
train_verdict_gate() {
    local _pr_json="$1"
    if printf '%s' "$_pr_json" | _gh_pr_merge_train_has_review_blocked_label; then
        printf 'skip:review-blocked — reviewer verdict is blocking\n'
    elif ! printf '%s' "$_pr_json" | _gh_pr_merge_train_has_review_passed_label; then
        printf 'skip:review not verified — no review-passed label\n'
    else
        printf 'proceed\n'
    fi
}

# Mirrors routing-table.md -> the four short-circuit conditions, in order.
# $1 = the F-3 `$STATE` blob. Echoes `proceed` or `skip:<reason>`.
#
# The verdict rows sit AFTER draft and reply-pending and BEFORE
# `mergeStateStatus` is read at all: a blocked PR must never be routed to a
# remediation atom, which would spend an F-5 attempt on a decision no rebase
# can change.
train_route_short_circuit() {
    local _state="$1"
    if printf '%s' "$_state" | jq -e '.isDraft == true' >/dev/null 2>&1; then
        printf 'skip:draft\n'
        return 0
    fi
    if printf '%s' "$_state" | _gh_pr_merge_train_has_reply_pending_label; then
        printf 'skip:reply-pending — review reply not yet complete\n'
        return 0
    fi
    train_verdict_gate "$_state"
}

# One `gh pr list --json` element / `gh pr view` blob, for the tests.
# $1 = PR number, $2 = raw JSON labels array, $3 = isDraft (default false).
verdict_pr() {
    printf '{"number":%s,"isDraft":%s,"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","labels":%s}' \
        "$1" "${3:-false}" "$2"
}
