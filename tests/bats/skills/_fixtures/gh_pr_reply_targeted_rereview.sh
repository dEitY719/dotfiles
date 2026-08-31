#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_reply_targeted_rereview.sh
# Source-of-truth mirror for gh:pr-reply Step 6's targeted re-review lane:
#   claude/skills/gh-pr-reply/references/targeted-rereview.md
#   claude/skills/gh-pr-reply/references/verdict-label-removal.sh.md
#
# Issue #1616. Like the merge-train verdict-gate fixture beside it, this does
# NOT re-implement the gate — it sources the shipped functions, so a mirror
# cannot pass while production drifts (#1524).
#
# Keep the ORDER and the report strings in sync with the doc.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_reply_targeted_review.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/devx_pr_review_all.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"

# Stands in for the doc's F-3 step: `Skill(gh:pr-review, "--ai <r> --paths
# <fixed files> <PR> <remote>")`, then `devx_pr_review_all_verdict` over the
# comment that run posts. Args: $1 reviewer, $2 pr, $3 repo, $4 paths,
# $5 post-push head sha. Echoes one verdict token.
#
# Tests set STUB_VERDICT_<reviewer>; the default `unknown` is deliberate —
# a lane that produced no readable verdict must never certify anything.
pr_reply_targeted_rereview() {
    printf 'gh:pr-review --ai %s --paths %s %s\n' "$1" "$4" "$2" >>"${LANE_LOG:-/dev/null}"
    case "$1" in
    codex) printf '%s\n' "${STUB_VERDICT_codex:-unknown}" ;;
    agy) printf '%s\n' "${STUB_VERDICT_agy:-unknown}" ;;
    claude) printf '%s\n' "${STUB_VERDICT_claude:-unknown}" ;;
    opencode) printf '%s\n' "${STUB_VERDICT_opencode:-unknown}" ;;
    hermes) printf '%s\n' "${STUB_VERDICT_hermes:-unknown}" ;;
    esac
}

# Mirrors verdict-label-removal.sh.md + targeted-rereview.md, in order:
#   1. `review-passed` is dropped unconditionally (the head advanced).
#   2. the per-reviewer gate decides whether the targeted lane may run.
#   3. only an independent re-review verdict may write a label, and it does
#      so through `devx_pr_review_all_apply_label` — never inline (NF-2).
#
# Usage: <origin lines> | pr_reply_step6 <pr> <repo> <host> <head-sha>
#            <space-separated fixed paths> <blocking-reviewer>...
pr_reply_step6() {
    local _pr="$1" _repo="$2" _host="$3" _sha="$4" _paths="$5"
    shift 5
    local _origins _decision _lanes _r _verdicts="" _label _report

    _origins=$(cat)

    _gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" >/dev/null 2>&1 || :

    _decision=$(printf '%s\n' "$_origins" | _gh_pr_reply_targeted_lane_decide "$@") || return $?

    case "$_decision" in
    lane=*)
        _lanes="${_decision#lane=}"
        # Word-split is the contract: `lane=` carries a space-separated list.
        # shellcheck disable=SC2086
        for _r in $_lanes; do
            _verdicts="${_verdicts}$(pr_reply_targeted_rereview "$_r" "$_pr" "$_repo" "$_paths" "$_sha")
"
        done
        _label=$(printf '%s' "$_verdicts" | devx_pr_review_all_aggregate | sed -n 's/^label=//p')
        printf '%s' "$_verdicts" |
            devx_pr_review_all_apply_label "$_pr" "$_repo" "$_host" "$_sha"
        case "$_label" in
        review-blocked) _report="verdict=blocking" ;;
        review-passed) _report="verdict=lgtm" ;;
        *) _report="verdict=unknown" ;;
        esac
        _gh_pr_reply_targeted_lane_report "$_report"
        ;;
    *)
        _gh_pr_reply_targeted_lane_report "$_decision"
        ;;
    esac
}
