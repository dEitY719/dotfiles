#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_resolve_outdated_review_passed.sh
# Source-of-truth mirror for gh:pr-resolve-outdated Step 5's `review-passed`
# reconciliation:
#   claude/skills/gh-pr-resolve-outdated/references/verdict-label-removal.sh.md
#   shell-common/functions/gh_pr_resolve_outdated.sh
#
# Issue #1698. Like the fixtures beside it, this does NOT re-implement the
# patch-id comparison or the label write/drop — it sources the shipped
# functions, so a mirror cannot pass while production drifts (#1524's rule).

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_resolve_outdated.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/devx_pr_review_all.sh"

# Mirrors Step 5's doc-documented variable names 1:1 — the doc itself pastes
# a call shaped exactly like this one.
#
# Usage: resolve_outdated_step5_reconcile <pr> <repo> <host> \
#            <old-base-sha> <old-head-sha> <new-base-sha> <new-head-sha> \
#            [worktree-path]
resolve_outdated_step5_reconcile() {
    _gh_pr_resolve_outdated_reconcile_review_passed "$@"
}
