#!/usr/bin/env bash
# tests/bats/functions/_fixtures/gh_pr_merge_train_review_verdict_gate.sh
# Loads the shipped shell SSOT the merge train's review verdict gate calls
# (#1564 / #1601): the label predicates and the sha-freshness check in
# gh_pr_merge_train.sh, and the self-heal drop in gh_pr_edit_safe.sh.
#
# #2200: the skill-mirror half (train_verdict_gate, train_route_short_circuit,
# train_verdict_gate_f3, verdict_pr) moved to the gh-pr-skills repo, where the
# tests run the shipped review-verdict-gate.md / routing-table.md blocks.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/lib/gh_pr_merge_train.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/lib/gh_pr_edit_safe.sh"
