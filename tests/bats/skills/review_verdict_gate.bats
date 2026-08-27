#!/usr/bin/env bats
# tests/bats/skills/review_verdict_gate.bats
# Issue #1527 — the review verdict is now a first-class pipeline state:
# devx:pr-review-all emits `review-blocked` / `review-passed`, and
# gh:pr-merge-train gates on it. Those three skills are Claude-driven, not
# shell functions, so what bats can pin here is that the contract does not
# silently drift back out of their instructions — the same drift-guard shape
# as gh_pr_merge_board_gate_retired.bats (#1513).
#
# The parsing/aggregation logic itself is unit-tested in
# tests/bats/functions/devx_pr_review_all_verdict.bats.

load '../test_helper'

setup() {
    setup_isolated_home
    SKILLS="${_BATS_REAL_DOTFILES_ROOT}/claude/skills"
}

teardown() {
    teardown_isolated_home
}

# ── producer: devx:pr-review-all ─────────────────────────────────────

@test "#1527: devx:pr-review-all has a verdict-label reference" {
    run test -f "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
}

@test "#1527: devx:pr-review-all SKILL.md has a verdict aggregation step" {
    run grep -F "Aggregate verdicts into the merge-gate label" \
        "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "#1527: devx:pr-review-all names both helper functions" {
    run grep -F "devx_pr_review_all_verdict" "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
    run grep -F "devx_pr_review_all_aggregate" "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "#1527: the label is applied through _gh_pr_edit_safe_label, not bare gh pr edit" {
    # Projects-classic GraphQL deprecation makes `gh pr edit --add-label`
    # exit 1 with the label silently dropped (#326).
    run grep -F "_gh_pr_edit_safe_label" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
    run grep -F "gh pr edit --add-label" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    # mentioned only as the thing NOT to use
    assert_output --partial "never bare"
}

# ── consumer: gh:pr-merge-train ──────────────────────────────────────

@test "#1527: gh:pr-merge-train has a review-verdict gate reference" {
    run test -f "${SKILLS}/gh-pr-merge-train/references/review-verdict-gate.md"
    assert_success
}

@test "#1527: the train's queue query requests labels" {
    # Without `labels` in the --json field set the gate has nothing to read.
    run grep -F "baseRefName,title,labels" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: the train's SKILL.md declares the verdict gate at queue construction" {
    run grep -F "Review verdict gate (#1527)" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: absence of a label is a skip, never a pass" {
    # The load-bearing rule. If this phrasing disappears the gate is a no-op
    # for every PR that was never reviewed — the exact #1518 hole.
    run grep -F "Absence is a skip, not a pass" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: the train is forbidden from treating an unlabelled PR as reviewed" {
    run grep -F "Never treat an unlabelled PR as reviewed" \
        "${SKILLS}/gh-pr-merge-train/references/constraints.md"
    assert_success
}

@test "#1527: the train does not parse review comment bodies" {
    run grep -F "never parses a review comment body" \
        "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

# ── release path: gh:pr-reply ────────────────────────────────────────

@test "#1527: gh:pr-reply has a review-blocked clear reference" {
    run test -f "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: gh:pr-reply clears review-blocked only after pushing an accepted fix" {
    run grep -F "PUSHED_FIXES" "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
    run grep -F "ACCEPTED_COUNT" "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: gh:pr-reply must never add review-passed" {
    run grep -F "never add \`review-passed\`" "${SKILLS}/gh-pr-reply/SKILL.md"
    assert_success
}

@test "#1527: gh:pr-reply removes the label via REST DELETE, not gh pr edit --remove-label" {
    run grep -F "gh pr edit --remove-label" \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_output --partial "not"
    run grep -F "gh api -X DELETE" \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

# ── the retired gate must not come back (#1513 interaction) ──────────

@test "#1527: the fix does not resurrect the board Approved gate (#1513)" {
    run grep -RF "Step 2-B" "${SKILLS}/devx-pr-review-all/"
    assert_failure
    run grep -F "GH_PR_MERGE_SKIP_BOARD_CHECK" \
        "${SKILLS}/gh-pr-merge-train/references/review-verdict-gate.md"
    assert_failure
}
