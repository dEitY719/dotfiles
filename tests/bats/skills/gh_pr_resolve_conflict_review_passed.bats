#!/usr/bin/env bats
# tests/bats/skills/gh_pr_resolve_conflict_review_passed.bats
# Issue #1700 — gh:pr-resolve-conflict Step 5's `review-passed` reconciliation:
#   claude/skills/gh-pr-resolve-conflict/references/verdict-label-removal.sh.md
#   shell-common/functions/gh_pr_resolve_outdated.sh
# Source-of-truth fixture: _fixtures/gh_pr_resolve_conflict_review_passed.sh
#
# Why this file exists next to the near-identical
# `gh_pr_resolve_outdated_review_passed.bats`: #1698 gave the patch-id
# reconciliation to exactly ONE of the two rebase+force-push skills. This one
# kept dropping `review-passed` unconditionally even though its own Step 3 can
# complete with ZERO conflicts — `git rebase` exits 0 on a PR GitHub merely
# MARKED `CONFLICTING`, producing the same content-identical rebase its sister
# skill already handles. Whichever skill happened to pick the PR up first
# decided the outcome (issue #1700, PR #1687). The helper is shared, so this
# file only pins that THIS skill's wrapper reaches it with its own variable
# names and the right argument order — the helper's own semantics stay pinned
# next door.
#
# Cases:
#   1. Zero-conflict rebase, patch-id identical, marker fresh for BACKUP_SHA ->
#      label preserved and re-stamped for the new head, no DELETE, and
#      `review-blocked` never touched (the #1700 scenario).
#   2. A rebase that genuinely changed content -> dropped, exactly as before.
#   3. A PR that was never reviewed (no marker) -> dropped; sharing the helper
#      must not let this skill manufacture a verdict either (#1699 guard).
#   4. `--worktree <path>` mode, which `gh:pr-merge-train` always uses.

# `_marker_comment`, the `gh`/`_gh_pr_edit_safe_label` stubs, and the rebase
# repo builder are shared with the sister `gh:pr-resolve-outdated` suite —
# see `_fixtures/review_passed_gh_stub.sh` (#1700).

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_resolve_conflict_review_passed.sh'
GH_STUB='tests/bats/skills/_fixtures/review_passed_gh_stub.sh'

setup() {
    setup_isolated_home
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    STUB_CURRENT_LABELS="${STUB_CURRENT_LABELS:-review-passed}"
    STUB_ME_LOGIN="${STUB_ME_LOGIN:-pipeline-bot}"
    : "${STUB_COMMENTS_JSON:=[]}"
    export STUB_CURRENT_LABELS STUB_ME_LOGIN STUB_COMMENTS_JSON
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${GH_STUB}"
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    _review_passed_gh_stub_setup
}

teardown() {
    teardown_isolated_home
}

# eval-friendly: exports REPO_DIR/OLD_BASE/BACKUP/NEW_BASE/NEW_HEAD_SAME/NEW_HEAD_DIFF.
# This skill names its pre-rebase head `BACKUP` (Step 1) where the sister
# suite reuses the same value under the name `OLD_HEAD` — see the fixture.
_1700_make_repo() {
    _review_passed_make_rebase_repo BACKUP
}

@test "conflict Step 5 (#1700): a zero-conflict rebase with identical content keeps review-passed" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    # #1563 / #1699: only devx:pr-review-all and gh:pr-reply may write this one.
    refute_output --partial 'review-blocked'
    assert_output --partial "add 1687 review-passed --repo acme/widget"
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}

@test "conflict Step 5 (#1700): a rebase that really changed content still drops" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_DIFF"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1687/labels/review-passed'
    refute_output --partial 'add 1687 review-passed'
}

@test "conflict Step 5 (#1700): a PR with no marker never earns the label from this skill" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_CURRENT_LABELS="test,fix"
    STUB_COMMENTS_JSON='[]'
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1687/labels/review-passed'
    refute_output --partial 'add 1687 review-passed'
}

@test "conflict Step 5 (#1700): works in --worktree mode, which gh:pr-merge-train always uses" {
    eval "$(_1700_make_repo)"
    cd "${BATS_TEST_TMPDIR}" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME" "$REPO_DIR"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}
