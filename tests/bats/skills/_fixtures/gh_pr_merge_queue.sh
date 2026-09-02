#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_queue.sh
# Source-of-truth mirror for the merge-queue path added by issue #1707:
#   claude/skills/gh-pr-merge/SKILL.md            (Step 1 flags, Step 3, Step 3.5)
#   claude/skills/gh-pr-merge/references/finalize-merged-pr.sh.md
#   claude/skills/gh-pr-merge-train/SKILL.md      (Step 0 finalize sweep)
#
# Two different kinds of thing live here, and the difference matters:
#
#   * `merge_queue_needs_finalize` does NOT re-implement its predicate — it
#     sources the shipped `gh_pr_merge_train.sh` and calls the real
#     `_gh_pr_merge_train_needs_finalize`, so a mirror can never pass while
#     production drifts (#1524's rule, same as the verdict-gate fixture).
#   * `merge_step3_auto` / `merge_step3_5` mirror bash blocks that only exist
#     as prose in a SKILL.md. Those are pinned by the drift-guard tests at the
#     bottom of gh_pr_merge_queue.bats — change the doc, change this file.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_merge_train.sh"

# --- the real shared predicate (gh:pr-merge-train Step 0) -----------------
#
# Usage: merge_queue_needs_finalize '<one gh pr list element>'
# rc 0 = this MERGED PR still owes a finalize pass.
merge_queue_needs_finalize() {
    printf '%s' "$1" | _gh_pr_merge_train_needs_finalize
}

# Usage: merge_queue_finalize_targets '<gh pr list --json ... array>'
# Echoes the filtered array (the real shared array-level filter, same rule as
# the single-PR predicate above).
merge_queue_finalize_targets() {
    printf '%s' "$1" | _gh_pr_merge_train_finalize_targets
}

# --- the two strict-relaxation predicates (Step 3.6) ----------------------
#
# Same rule as above: these call the real shipped functions, never a copy.
#
# Usage: train_behind_may_merge_directly '<rules/branches/<base> JSON>'
train_behind_may_merge_directly() {
    printf '%s' "$1" | _gh_pr_merge_train_behind_may_merge_directly
}

# Usage: train_base_ci_red '<check-runs JSON>' <required-context>...
train_base_ci_red() {
    local _json="$1"
    shift
    printf '%s' "$_json" | _gh_pr_merge_train_base_ci_red "$@"
}

# --- gh:pr-merge-train Step 3.6, the per-base guard -----------------------
#
# Mirrors the block in
# gh-pr-merge-train/references/strict-mode-relaxation.md → "New: the train
# refuses to pile onto a red base". Pinned by the drift guards at the bottom of
# gh_pr_merge_queue.bats — change the doc, change this file.
#
# Echoes the verdict line the train reports, or nothing when the merge phase
# may proceed. `$BASE_RULES` / `$BASE_CHECKS` stand in for the two `gh api`
# responses so the tests can drive every branch without a network.
#
# Usage: train_step3_6 <base> <rules-json-or-empty> <checks-json-or-empty>
train_step3_6() {
    local BASE="$1" BASE_RULES="$2" BASE_CHECKS="$3" BEHIND_DIRECT=no _ctx
    local BASE_CONTEXTS=()

    printf '%s' "$BASE_RULES" | _gh_pr_merge_train_behind_may_merge_directly && BEHIND_DIRECT=yes

    while IFS= read -r _ctx; do
        [ -n "$_ctx" ] && BASE_CONTEXTS+=("$_ctx")
    done <<EOF
$(printf '%s' "$BASE_RULES" | jq -r '.[]? | select(.type == "required_status_checks")
                                          | .parameters.required_status_checks[]?.context' 2>/dev/null)
EOF

    printf 'BEHIND_DIRECT=%s\n' "$BEHIND_DIRECT"
    if [ "$BEHIND_DIRECT" = yes ] && [ -z "$BASE_CHECKS" ]; then
        echo "[SKIPPED] base health unreadable on $BASE — not merging onto an unverified base"
    elif printf '%s' "$BASE_CHECKS" | _gh_pr_merge_train_base_ci_red "${BASE_CONTEXTS[@]}"; then
        echo "[SKIPPED] $BASE is red — halting the merge phase until it is green"
    fi
}

# --- gh:pr-merge Step 3, the `--auto` form -------------------------------
#
# Mirrors SKILL.md Step 3's `--auto` block. The fallback is the contract: any
# failure of the `--auto` form retries the exact command the skill has always
# run, so the flag can never be the reason a merge fails. No error-string
# matching, deliberately.
#
# Usage: merge_step3_auto <pr> <repo> <host> <strategy-flag>
merge_step3_auto() {
    local PR_NUMBER="$1" TARGET_REPO="$2" TARGET_HOST="$3" STRATEGY_FLAG="$4" MERGE_OUT
    if MERGE_OUT=$(GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
        "$STRATEGY_FLAG" --delete-branch --auto 2>&1); then
        printf '%s\n' "$MERGE_OUT"
    else
        printf '[INFO] gh:pr-merge: --auto refused (%s) — retrying the plain merge.\n' \
            "$(printf '%s' "$MERGE_OUT" | tr '\n' ' ')"
        GH_HOST="$TARGET_HOST" gh pr merge "$PR_NUMBER" --repo "$TARGET_REPO" \
            "$STRATEGY_FLAG" --delete-branch
    fi
}

# --- gh:pr-merge Step 3.5, the third outcome ------------------------------
#
# Mirrors SKILL.md Step 3.5. `--auto` returning success means GitHub accepted
# responsibility for the merge, NOT that the PR is merged: re-read the state
# and route on it. OPEN means queued — print `[QUEUED]` and run none of the
# completion sequence, so the `review-passed` label survives as the signal
# gh:pr-merge-train's Step 0 sweep matches on.
#
# `merge_finalize_sequence` stands in for Steps 4+5, whose real blocks each
# have their own SSOT (references/finalize-merged-pr.sh.md indexes them). The
# tests only need to observe WHETHER it ran.
#
# Usage: merge_step3_5 <pr> <repo> <host>
merge_step3_5() {
    local _pr="$1" _repo="$2" _host="$3" _state _head _base _url _json
    _json=$(GH_HOST="$_host" gh pr view "$_pr" --repo "$_repo" \
        --json state,mergedAt,headRefName,baseRefName,url)
    _state=$(printf '%s' "$_json" | jq -r '.state // empty')
    case "$_state" in
    MERGED)
        merge_finalize_sequence "$_pr"
        ;;
    OPEN)
        _head=$(printf '%s' "$_json" | jq -r '.headRefName // empty')
        _base=$(printf '%s' "$_json" | jq -r '.baseRefName // empty')
        _url=$(printf '%s' "$_json" | jq -r '.url // empty')
        merge_queued_report "$_pr" "$_head" "$_base" "$_url"
        ;;
    *)
        printf '[FAIL] PR #%s not merged — closed\n' "$_pr"
        ;;
    esac
}

# The `[QUEUED]` report shape, verbatim from SKILL.md Step 3.5.
merge_queued_report() {
    printf '[QUEUED] PR #%s added to merge queue — not yet merged\n' "$1"
    printf '  Branch:  %s → %s\n' "$2" "$3"
    printf '  URL:     %s\n' "$4"
}

# Stand-in for the Steps 4+5 completion sequence. Records that it ran so the
# tests can assert the `[QUEUED]` branch skips it entirely.
merge_finalize_sequence() {
    printf 'finalize:%s\n' "$1" >>"${FINALIZE_LOG:-/dev/null}"
    printf '[OK] PR #%s merged (rebase)\n' "$1"
}
