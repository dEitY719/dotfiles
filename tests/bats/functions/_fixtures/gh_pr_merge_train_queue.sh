#!/usr/bin/env bash
# tests/bats/functions/_fixtures/gh_pr_merge_train_queue.sh
# The shell-common half of the #1707 merge-queue fixture: thin wrappers that
# source the shipped `gh_pr_merge_train.sh` and call the real predicates, so a
# test can never pass while production drifts (#1524's rule).
#
# The other half — mirrors of the skill text (gh-pr:merge Step 3 `--auto`,
# Step 3.5 `[QUEUED]`, gh-pr:merge-train Step 3.6 base guard, Step 0 finalize
# sweep) — moved to dEitY719/gh-pr-skills tests/bats/gh_pr_merge_train_queue.bats
# by #2219, where it evals the shipped fences instead of a hand copy.

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

# Usage: train_base_strict_confirmed '<rules/branches/<base> JSON>'
train_base_strict_confirmed() {
    printf '%s' "$1" | _gh_pr_merge_train_base_strict_confirmed
}

# Usage: train_base_ci_red '<check-runs JSON>' <required-context>...
train_base_ci_red() {
    local _json="$1"
    shift
    printf '%s' "$_json" | _gh_pr_merge_train_base_ci_red "$@"
}
