#!/usr/bin/env bats
# tests/bats/skills/gh_pr_reply_review_passed_gate.bats
# Issue #1636 — gh:pr-reply Step 6's `review-passed` gate, end to end:
#   claude/skills/gh-pr-reply/references/review-passed-gate.md   (procedure SSOT)
#   claude/skills/gh-pr-reply/references/verdict-label-removal.sh.md
#   claude/skills/gh-pr-reply/references/final-summary.md
#   claude/skills/gh-pr-reply/references/constraints.md
# Source-of-truth fixture: _fixtures/gh_pr_reply_review_passed_gate.sh
#
# Supersedes gh_pr_reply_targeted_rereview.bats (#1616), whose subject — a
# scoped `gh:pr-review` re-call that had to return a non-blocking verdict
# before `review-passed` could be written — no longer exists. Those tests are
# REWRITTEN here rather than dropped: they pinned NF-2's "never self-certify"
# rule, which #1636 deliberately relaxed on this one path, so the file now
# pins the new policy explicitly instead of silently losing the old one.
#
# The fixture does NOT re-implement the gate — it sources the shipped
# shell-common/functions/gh_pr_reply_targeted_review.sh and the shipped
# devx_pr_review_all.sh, so a mirror cannot pass while the production
# functions drift (#1524's rule).
#
# Acceptance criteria from the issue, in order:
#   AC-1 all comments replied, no unresolved BLOCKER -> review-passed applied
#        (freshness marker included), with NO external CLI re-call
#   AC-2 no BLOCKER item at all -> review-passed applied
#   AC-3 one unresolved BLOCKER -> review-passed NOT applied, nothing written
#   AC-4 review-passed is still invalidated on every push (unchanged rule)
#   AC-5 the label write stays soft-fail

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_reply_review_passed_gate.sh'

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-reply"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return 0
    }
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    _gh_pr_edit_safe_label() {
        printf 'add %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return "${STUB_ADD_RC:-0}"
    }
}

teardown() {
    teardown_isolated_home
}

# The PR #1609 shape: codex raised (and got) 2 BLOCKER fixes, agy raised 3
# non-blocking FOLLOW-UPs that were all validly declined.
_origins_1609() {
    printf '%s\n' \
        codex:BLOCKER:ACCEPT \
        codex:BLOCKER:ACCEPT \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE
}

# ---------------------------------------------------------------------
# AC-1 — the pass path
# ---------------------------------------------------------------------

@test "AC-1: a non-blocking reviewer's DECLINE no longer pins review-blocked" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "AC-1: every BLOCKER resolved -> review-passed is applied" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed --repo acme/widget'
}

# The whole point of #1636: the label is re-earned without paying for an
# external reviewer round-trip. Nothing in this path may shell out to a CLI.
@test "AC-1 (#1636): no reviewer CLI and no gh:pr-review call is made" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    refute_output --partial '--ai '
    refute_output --partial '--paths'
    refute_output --partial 'pr-review'
    refute_output --partial 'pr diff'
}

@test "AC-1 (NF-1): the label carries the POST-push head sha as its freshness marker" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "AC-1: every gh call pins the target host (#1403 / #1407)" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run grep -c 'GH_HOST=ghe.example.com' "$GH_LOG"
    assert_success
    refute_output '0'
}

@test "AC-1: the reported line says the label was earned without a re-review" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha"
    assert_success
    assert_output --partial 'review-passed 적용'
    assert_output --partial '외부 재검토 없음'
}

# ---------------------------------------------------------------------
# AC-2 — nothing blocked in the first place
# ---------------------------------------------------------------------

@test "AC-2: a PR whose comments were all non-blocking earns review-passed" {
    printf '%s\n' agy:FOLLOW-UP:DECLINE agy:Suggestion:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed'
}

@test "AC-2: ACCEPT-PARTIAL on a BLOCKER counts as resolved" {
    printf '%s\n' codex:BLOCKER:ACCEPT-PARTIAL |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed'
}

# ---------------------------------------------------------------------
# AC-3 — the fail-closed half, unchanged by the relaxation
# ---------------------------------------------------------------------

@test "AC-3: a DECLINEd BLOCKER never adds review-passed" {
    printf '%s\n' codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
}

@test "AC-3: a QUESTION on a BLOCKER never adds review-passed" {
    printf '%s\n' codex:BLOCKER:QUESTION |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
}

@test "AC-3: an unresolved BLOCKER leaves review-blocked untouched" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-blocked'
}

@test "AC-3: the report says the label is held and names the reviewer" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 0; }
        printf '%s\n' codex:BLOCKER:DECLINE | pr_reply_step6 1609 acme/widget '' newsha"
    assert_success
    assert_output --partial 'codex'
    assert_output --partial 'review-blocked 유지'
    assert_output --partial 'review-passed 미부여'
}

@test "AC-3: no freshness marker is posted when the gate holds" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'review-verdict:review-passed'
}

# ---------------------------------------------------------------------
# AC-4 — the #1563 invalidation rule is unchanged
# ---------------------------------------------------------------------

@test "AC-4: review-passed is still invalidated on every push" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-passed'
}

# Order matters: the invalidation drop runs BEFORE the gate re-applies, or the
# skill would delete the label it just earned.
@test "AC-4: the invalidation drop precedes the re-apply" {
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha
    run bash -c "grep -n 'labels/review-passed\|add 1609 review-passed' '$GH_LOG' | head -2 | tr '\n' '|'"
    assert_output --partial 'DELETE'
    run bash -c "grep -n 'review-passed' '$GH_LOG' | head -1"
    assert_output --partial 'DELETE'
}

@test "AC-4: with no push there is no invalidation, and the gate still runs" {
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 0
    run cat "$GH_LOG"
    refute_output --partial 'DELETE repos/acme/widget/issues/1609/labels/review-passed'
    assert_output --partial 'add 1609 review-passed'
}

# ---------------------------------------------------------------------
# AC-5 — soft-fail
# ---------------------------------------------------------------------

@test "AC-5: a failing label add warns and leaves the PR unlabelled, rc 0" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 1; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha"
    assert_success
    assert_output --partial '미검증으로 취급'
}

@test "AC-5: a missing label in the repo points at gh:label-bootstrap" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 3; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha"
    assert_success
    assert_output --partial 'gh:label-bootstrap'
}

# ---------------------------------------------------------------------
# Doc guards — the fixture is only trustworthy while the docs agree
# ---------------------------------------------------------------------

@test "doc-guard: review-passed-gate.md exists and names the gate functions" {
    run grep -qF -- '_gh_pr_reply_review_passed_gate' \
        "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_origin_line' \
        "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_apply_review_passed' \
        "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
}

@test "doc-guard: the gate doc routes the label through the shared writer" {
    run grep -qF -- 'devx_pr_review_all_write_label' \
        "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
}

@test "doc-guard: the gate doc forbids fabricating a verdict token" {
    # The one shortcut #1636 rules out: feeding a synthetic `lgtm` through
    # devx_pr_review_all_apply_label to dress this skill's judgment up as a
    # reviewer CLI's opinion.
    run grep -qF -- 'devx_pr_review_all_apply_label' \
        "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
    run grep -q '을 쓰지 않는다' "${SKILL_DIR}/references/review-passed-gate.md"
    assert_success
}

@test "doc-guard: the #1616 targeted-rereview doc is gone, not left contradicting" {
    [ ! -e "${SKILL_DIR}/references/targeted-rereview.md" ] ||
        fail 'targeted-rereview.md still exists — it documents a lane #1636 removed'
}

# The relaxation is a safety-principle change; this repo documents those
# loudly. A silent deletion of the old NF-2 bullet would be the failure mode.
@test "doc-guard: constraints.md states the NF-2 relaxation, its scope and its reason" {
    local _c="${SKILL_DIR}/references/constraints.md"
    run grep -qF -- 'NF-2' "$_c"
    assert_success
    run grep -q 'RELAXED' "$_c"
    assert_success
    run grep -qF -- '#1636' "$_c"
    assert_success
    run grep -q 'trade-off' "$_c"
    assert_success
}

@test "doc-guard: constraints.md still pins the fail-closed half" {
    local _c="${SKILL_DIR}/references/constraints.md"
    run grep -q 'fail-closed' "$_c"
    assert_success
    run grep -q 'not verified' "$_c"
    assert_success
}

@test "doc-guard: constraints.md still forbids hand-written labels" {
    run grep -q 'Never \*\*add\*\*' "${SKILL_DIR}/references/constraints.md"
    assert_success
}

# The whole of #1616: this exact expression is what pinned review-blocked on
# PR #1609. Its removal was the fix, so its return is the regression.
@test "doc-guard: the global DECLINED_COUNT gate is gone from the removal doc" {
    run grep -qE 'DECLINED_COUNT.*-eq 0|DECLINED_COUNT == 0' \
        "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_failure
}

@test "doc-guard: the removal doc still drops review-passed unconditionally on push" {
    run grep -qF -- 'review-passed' "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_success
    run grep -qF -- '_gh_pr_drop_label' "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_success
}

@test "doc-guard: the removal doc hands review-blocked to the gate" {
    run grep -qF -- 'review-passed-gate.md' \
        "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_success
}

# The invalidation SSOT lives in the shell library's header (#1563). It
# spelled the replaced global rule out verbatim; leaving it there would make
# the SSOT contradict the shipped behaviour.
@test "doc-guard: the #1563 invalidation SSOT no longer states the global counter rule" {
    run grep -qE 'ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_failure
}

@test "doc-guard: the #1563 invalidation SSOT points at the current gate" {
    run grep -qF -- '_gh_pr_reply_review_passed_gate' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}

@test "doc-guard: the #1563 invalidation SSOT records the NF-2 relaxation" {
    run grep -qF -- '#1636' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
    run grep -q 'RELAXED' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}

# devx:pr-review-all's reference doc is the label-lifecycle SSOT. A reader who
# did not know the ownership moved would conclude a `review-passed` written by
# a gh:pr-reply pass was forged.
@test "doc-guard: the label-lifecycle SSOT names gh:pr-reply as the review-passed producer" {
    local _producer="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/review-verdict-label.md"
    run grep -qF -- '#1636' "$_producer"
    assert_success
    run grep -qF -- 'gh:pr-reply' "$_producer"
    assert_success
    run grep -qF -- 'review-passed-gate.md' "$_producer"
    assert_success
}

@test "doc-guard: SKILL.md Step 3 records the per-reviewer origin token" {
    run grep -qF -- '<reviewer>:<severity>:<verdict>' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: SKILL.md Step 6 runs the gate and names its helper" {
    run grep -qF -- 'review-passed-gate.md' "${SKILL_DIR}/SKILL.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_apply_review_passed' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: SKILL.md Step 6 no longer re-invokes gh:pr-review" {
    run grep -qF -- 'Skill(gh:pr-review' "${SKILL_DIR}/SKILL.md"
    assert_failure
}

@test "doc-guard: final-summary.md reports the per-reviewer breakdown and the gate outcome" {
    run grep -qF -- '_gh_pr_reply_origin_tally' "${SKILL_DIR}/references/final-summary.md"
    assert_success
    run grep -qF -- 'review-passed' "${SKILL_DIR}/references/final-summary.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_apply_review_passed' "${SKILL_DIR}/references/final-summary.md"
    assert_success
}
