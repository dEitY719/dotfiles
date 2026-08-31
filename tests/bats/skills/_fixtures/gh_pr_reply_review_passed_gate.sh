#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_reply_review_passed_gate.sh
# Source-of-truth mirror for gh:pr-reply Step 6's `review-passed` gate:
#   claude/skills/gh-pr-reply/references/review-passed-gate.md
#   claude/skills/gh-pr-reply/references/verdict-label-removal.sh.md
#
# Issue #1636 (supersedes the #1616 targeted-re-review fixture this replaces).
# Like the merge-train verdict-gate fixture beside it, this does NOT
# re-implement the gate — it sources the shipped functions, so a mirror cannot
# pass while production drifts (#1524).
#
# Keep the ORDER and the report strings in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_reply_targeted_review.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/devx_pr_review_all.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Mirrors verdict-label-removal.sh.md + review-passed-gate.md. The ORDER below
# is load-bearing at every step, and PR #1637's review is why steps 2-4 exist
# at all:
#
#   1. `review-passed` is dropped when (and only when) a push advanced head.
#      Before the gate, or it would delete the label the gate just applied.
#   2. the PR's comments (already fetched in Step 2 — no extra API call) yield
#      the ORIGIN HISTORY of earlier passes and the external-review EVIDENCE
#      probe. Before the merge, which consumes the history. Since #1639 both
#      readers take the RAW comments JSON (`.user.login` intact) and a
#      required <expected-login>, and only trust that login's markers — a
#      forged ledger or `ai-review` marker from any commenter used to unlock
#      the gate outright.
#   3. this pass's ORIGINS are merged over that history, per-reviewer
#      supersede. Before the ledger AND the gate, because both read the merged
#      stream — the gate must see an earlier pass's DECLINEd BLOCKER that
#      Step 2's dedup hid from this pass (codex BLOCKER).
#   4. the merged stream is written back as the ledger comment — BEFORE the
#      gate and REGARDLESS of its outcome, because the hold case is exactly
#      when the next pass needs to be told.
#   5. the gate + write go through `_gh_pr_reply_apply_review_passed`, which
#      routes to the shared `devx_pr_review_all_write_label` primitive. There
#      is no inline label command anywhere in this path, and no reviewer CLI
#      is called (#1636).
#
# Usage: <this pass's origin lines> | pr_reply_step6 <pr> <repo> <host> <head-sha>
#            [<pushed-fixes>]          # default 1
#            [<comments-json-file>]    # default: no comments -> no evidence
#            [<expected-login>]        # default: pipeline-bot
pr_reply_step6() {
    local _pr="$1" _repo="$2" _host="$3" _sha="$4" _pushed="${5-1}" _bodies="${6-}" \
        _login="${7-pipeline-bot}"
    local _origins _history _evidence _merged

    _origins=$(cat)

    if [ "$_pushed" -gt 0 ]; then
        _gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" >/dev/null 2>&1 || :
    fi

    if [ -n "$_bodies" ] && [ -r "$_bodies" ]; then
        _history=$(_gh_pr_reply_history_origins "$_login" <"$_bodies")
        if _gh_pr_reply_history_has_review "$_login" <"$_bodies"; then
            _evidence=yes
        else
            _evidence=no
        fi
    else
        _history=""
        _evidence=no
    fi

    _merged=$(printf '%s\n' "$_origins" | _gh_pr_reply_origins_merge "$_history")

    printf '%s\n' "$_merged" |
        _gh_pr_reply_post_origins_ledger "$_pr" "$_repo" "$_host" "$_sha"

    printf '%s\n' "$_merged" |
        _gh_pr_reply_apply_review_passed "$_pr" "$_repo" "$_host" "$_sha" "$_evidence"
}
