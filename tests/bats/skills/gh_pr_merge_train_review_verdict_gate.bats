#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_review_verdict_gate.bats
# The merge train's review verdict gate (#1564, umbrella #1527):
#   claude/skills/gh-pr-merge-train/references/review-verdict-gate.md
#   claude/skills/gh-pr-merge-train/references/routing-table.md
#   claude/skills/gh-pr-merge-train/references/report-format.md
# Source-of-truth fixture: _fixtures/gh_pr_merge_train_review_verdict_gate.sh
#
# Issue #1564 verification checklist:
#   review-blocked / no label / review-passed  -> [SKIPPED] · [SKIPPED] · proceed
#   review-blocked beats a stale review-passed
#   the gate runs AFTER _gh_pr_merge_train_filter_targets, independently of it
#   gh:label-bootstrap provisions both labels and --prune preserves them
#     (covered in tests/bats/skills/gh_label_bootstrap.bats)
#   no code path in the train parses a review comment body

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_merge_train_review_verdict_gate.sh'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# The decision table
# ---------------------------------------------------------------------

@test "gate: review-blocked -> [SKIPPED] with the blocking reason" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: no verdict label at all -> [SKIPPED] review not verified" {
    run train_verdict_gate "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# Absence is the third state and it must stay a skip. Merging an unreviewed PR
# is the failure #1527 reproduced (PR #1518 -> #1520 -> PR #1522); a skip is
# one label away from moving.
@test "gate: an unrelated label is still 'not verified'" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"enhancement"},{"name":"ai"}]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "gate: review-passed alone -> stays in the queue" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

@test "gate: review-passed alongside unrelated labels still proceeds" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"fix"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# #1563's invalidation should make this unreachable, but a gate on a merge has
# to be deterministic about a state it does not expect. Blocked wins.
@test "gate: review-blocked beats a stale review-passed" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: label order does not change the verdict" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# A `gh pr list` whose --json projection omitted `labels` must read as "not
# verified", never as a pass — the same fail-closed direction as everywhere
# else in this train.
@test "gate: a PR object with no labels field is 'not verified'" {
    run train_verdict_gate '{"number":11,"isDraft":false}'
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# ---------------------------------------------------------------------
# routing-table.md F-3 — the mid-run re-check
# ---------------------------------------------------------------------
#
# A deferred devx:pr-review-all pass can add or flip a verdict label minutes
# after Step 2 built the queue. F-3's re-query is the only thing that sees it,
# so the verdict rows have to short-circuit the D-1 table the same way
# `reply-pending` does — before `mergeStateStatus` is read at all.

@test "F-3: a mid-run review-blocked short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3: a mid-run label loss short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3: review-passed lets the PR reach the D-1 table" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# Order among the short-circuits: draft and reply-pending are answered first,
# so their (more specific) reasons are what the report shows.
@test "F-3: draft outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]' true)"
    assert_success
    assert_output 'skip:draft'
}

@test "F-3: reply-pending outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit \
        "$(verdict_pr 11 '[{"name":"reply-pending"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:reply-pending — review reply not yet complete'
}

# ---------------------------------------------------------------------
# Independence from the Step 2 array filter (#1564 verification item)
# ---------------------------------------------------------------------
#
# The two filters answer different questions and a PR must pass BOTH. The
# verdict gate deliberately does NOT live inside
# `_gh_pr_merge_train_filter_targets`: that one drops its rejects silently,
# before the queue exists, and report-format.md documents those PRs as never
# listed — which would hide this gate's entire output.

@test "independence: the array filter passes a review-blocked PR through" {
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh'
        printf '%s' '[{\"number\":11,\"updatedAt\":\"2020-01-01T00:00:00Z\",\"isDraft\":false,\"labels\":[{\"name\":\"review-blocked\"}]}]' \
          | _gh_pr_merge_train_filter_targets --now 1800000000 | jq -r '.[].number'"
    assert_success
    assert_output "11"
}

@test "independence: the gate then rejects that same PR" {
    run train_verdict_gate '{"number":11,"labels":[{"name":"review-blocked"}]}'
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# ---------------------------------------------------------------------
# Doc guards — the fixture above is only trustworthy while the docs agree
# ---------------------------------------------------------------------

@test "doc-guard: review-verdict-gate.md exists and carries the decision table" {
    run grep -q 'review-blocked — reviewer verdict is blocking' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
    run grep -q 'review not verified — no review-passed label' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

@test "doc-guard: review-verdict-gate.md states absence is blocking" {
    run grep -q 'Why absence is blocking' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

# #1564 explicitly rules a time backstop out. A future edit that adds one
# would weaken the gate rather than bound it — fail here instead.
@test "doc-guard: review-verdict-gate.md rules out a time backstop" {
    run grep -q 'Why no time backstop' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
    run grep -qE '_gh_pr_merge_train_review_(blocked|passed)_stale_minutes' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_failure
}

@test "doc-guard: no staleness window function exists for the verdict labels" {
    run grep -qE '_gh_pr_merge_train_review_(blocked|passed)_stale_minutes' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_merge_train.sh"
    assert_failure
}

@test "doc-guard: the board Approved gate is not revived" {
    run grep -q 'Not the board `Approved` gate' \
        "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

@test "doc-guard: SKILL.md runs the gate and names the shared predicates" {
    run grep -qF -- '_gh_pr_merge_train_has_review_blocked_label' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_has_review_passed_label' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- 'Step 3.5' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: routing-table.md re-checks both verdict labels per PR" {
    run grep -qF -- '_gh_pr_merge_train_has_review_blocked_label' \
        "${SKILL_DIR}/references/routing-table.md"
    assert_success
    run grep -qF -- '_gh_pr_merge_train_has_review_passed_label' \
        "${SKILL_DIR}/references/routing-table.md"
    assert_success
}

@test "doc-guard: report-format.md tables both new [SKIPPED] reasons" {
    run grep -q 'review-blocked — reviewer verdict is blocking' \
        "${SKILL_DIR}/references/report-format.md"
    assert_success
    run grep -q 'review not verified — no review-passed label' \
        "${SKILL_DIR}/references/report-format.md"
    assert_success
}

# The failure direction is the whole design: parsing here would let a reviewer
# reformatting its verdict line silently UNLOCK the gate.
@test "doc-guard: the train never parses a review comment body" {
    run grep -rqE 'issues/[^ ]*/comments|ai-review:' "${SKILL_DIR}"
    assert_failure
}

# The producer side has to stay the only writer, or the gate becomes circular.
@test "doc-guard: the producer SSOT is linked from the gate doc" {
    run grep -q 'review-verdict-label.md' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}

# Without provisioning, _gh_pr_edit_safe_label rc 3 means the producer can
# never issue either label and every PR skips forever (#326).
@test "doc-guard: the gate doc names the provisioning path" {
    run grep -q 'gh:label-bootstrap' "${SKILL_DIR}/references/review-verdict-gate.md"
    assert_success
}
