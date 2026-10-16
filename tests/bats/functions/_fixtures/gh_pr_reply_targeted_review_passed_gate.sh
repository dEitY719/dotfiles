#!/usr/bin/env bash
# tests/bats/functions/_fixtures/gh_pr_reply_targeted_review_passed_gate.sh
# Loads the shipped shell SSOT behind gh-pr:reply Step 6's `review-passed`
# gate (#1636): gh_pr_reply_targeted_review.sh (gate, ledger, evidence probe),
# devx_pr_review_all.sh (the label-write primitive) and gh_pr_edit_safe.sh.
#
# #2200: the skill-mirror half (pr_reply_step6) moved to the gh-pr-skills repo,
# where the tests run the shipped review-passed-gate.md blocks.

# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_reply_targeted_review.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/devx_pr_review_all.sh"
# shellcheck source=/dev/null
. "${_BATS_REAL_DOTFILES_ROOT:-${DOTFILES_ROOT}}/shell-common/functions/gh_pr_edit_safe.sh"
