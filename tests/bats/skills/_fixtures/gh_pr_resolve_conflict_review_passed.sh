#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_resolve_conflict_review_passed.sh
# Source-of-truth mirror for gh:pr-resolve-conflict Step 5's `review-passed`
# handling:
#   claude/skills/gh-pr-resolve-conflict/references/verdict-label-removal.sh.md
#   shell-common/functions/gh_pr_resolve_outdated.sh
#
# Issue #1700. Like its gh:pr-resolve-outdated sibling beside it, this does NOT
# re-implement the patch-id comparison or the label write/drop — it sources the
# shipped functions, so a mirror cannot pass while production drifts (#1524).

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_resolve_outdated.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_merge_train.sh"

# Mirrors Step 5's doc-documented variable names 1:1 — the doc itself pastes a
# call shaped exactly like this one. `gh:pr-resolve-conflict` names its
# pre-rebase head `BACKUP_SHA` (Step 1) where `gh:pr-resolve-outdated` reuses
# the same value under the name `OLD_HEAD_SHA`; the shared helper is positional,
# so the two skills differ only in what they call the argument.
#
# Usage: resolve_conflict_step5_reconcile <pr> <repo> <host> \
#            <old-base-sha> <backup-sha> <new-base-sha> <new-head-sha> \
#            [worktree-path]
resolve_conflict_step5_reconcile() {
    _gh_pr_resolve_outdated_reconcile_review_passed "$@"
}
