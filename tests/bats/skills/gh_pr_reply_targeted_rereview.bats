#!/usr/bin/env bats
# tests/bats/skills/gh_pr_reply_targeted_rereview.bats
# Issue #1616 — gh:pr-reply Step 6's targeted re-review lane, end to end:
#   claude/skills/gh-pr-reply/references/targeted-rereview.md   (procedure SSOT)
#   claude/skills/gh-pr-reply/references/verdict-label-removal.sh.md
#   claude/skills/gh-pr-reply/references/final-summary.md
#   claude/skills/gh-pr-reply/references/constraints.md
# Source-of-truth fixture: _fixtures/gh_pr_reply_targeted_rereview.sh
#
# The fixture does NOT re-implement the gate — it sources the shipped
# shell-common/functions/gh_pr_reply_targeted_review.sh and the shipped
# devx_pr_review_all.sh, so a mirror cannot pass while the production
# functions drift (#1524's rule).
#
# Acceptance criteria from the issue, in order:
#   AC-1 blocking reviewer fully ACCEPTed + another reviewer's DECLINE
#        -> review-blocked is not left stuck; the targeted lane runs
#   AC-2 non-blocking re-review -> review-blocked dropped, review-passed
#        applied, WITHOUT a devx:pr-review-all fan-out
#   AC-3 still-blocking re-review -> review-blocked kept + said so
#   AC-4 any originally-blocking item still DECLINEd -> lane never called
#   AC-5 reviewer CLI absent / non-internal env -> "full re-run needed"

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_reply_targeted_rereview.sh'

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-reply"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    LANE_LOG="${BATS_TEST_TMPDIR}/lane.log"
    : >"$GH_LOG"
    : >"$LANE_LOG"
    export GH_LOG LANE_LOG
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    # Every reviewer CLI is present unless a test says otherwise.
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_reply_lane_available() { return 0; }
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return 0
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
# AC-1 / AC-2
# ---------------------------------------------------------------------

@test "AC-1: a non-blocking reviewer's DECLINE no longer pins review-blocked" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh b.sh' codex
    run cat "$LANE_LOG"
    assert_output --partial 'gh:pr-review --ai codex'
}

@test "AC-1: the targeted call is scoped to the fix commit's files only" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh b.sh' codex
    run cat "$LANE_LOG"
    assert_output --partial '--paths a.sh b.sh'
}

@test "AC-2: a non-blocking re-review applies review-passed" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial 'pr edit 1609 --repo acme/widget --add-label review-passed'
}

@test "AC-2: applying review-passed deletes review-blocked first" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "AC-2: only the ONE targeted lane runs — no devx:pr-review-all fan-out" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run cat "$LANE_LOG"
    assert_output --partial '--ai codex'
    refute_output --partial '--ai agy'
    refute_output --partial '--ai opencode'
    refute_output --partial '--ai hermes'
    run bash -c "wc -l <'$LANE_LOG'"
    assert_output '1'
}

@test "AC-2 (NF-1): the label carries the POST-push head sha as its freshness marker" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "AC-2: every gh call pins the target host (#1403 / #1407)" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run grep -c 'GH_HOST=ghe.example.com' "$GH_LOG"
    assert_success
    refute_output '0'
}

@test "AC-2: CONCERNS is non-blocking too" {
    STUB_VERDICT_codex=concerns
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial '--add-label review-passed'
}

# ---------------------------------------------------------------------
# AC-3 — still blocking
# ---------------------------------------------------------------------

@test "AC-3: a still-blocking re-review keeps review-blocked" {
    STUB_VERDICT_codex=blocking
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial '--add-label review-blocked'
    refute_output --partial '--add-label review-passed'
}

@test "AC-3: the report says the targeted re-review is still blocking" {
    STUB_VERDICT_codex=blocking
    run bash -c "STUB_VERDICT_codex=blocking
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        _gh_pr_reply_lane_available() { return 0; }
        gh() { return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha a.sh codex"
    assert_success
    assert_output --partial '타겟 재검토도 여전히 BLOCKING — 재수정 필요'
}

# ---------------------------------------------------------------------
# AC-4 — an unresolved blocker never spends an API call
# ---------------------------------------------------------------------

@test "AC-4: a DECLINEd BLOCKER never calls the targeted lane" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        _gh_pr_reply_lane_available() { return 0; }
        gh() { printf 'gh %s\n' \"\$*\" >>'$GH_LOG'; return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE \
          | pr_reply_step6 1609 acme/widget '' newsha a.sh codex"
    assert_success
    assert_output --partial 'review-blocked 유지'
    run cat "$LANE_LOG"
    assert_output ''
}

@test "AC-4: an unresolved blocker never adds review-passed" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' codex
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

@test "AC-4: review-passed is still invalidated on every push (unchanged rule)" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-passed'
}

# ---------------------------------------------------------------------
# AC-5 — the safe fallback
# ---------------------------------------------------------------------

@test "AC-5: an unavailable reviewer CLI asks for the full re-run and calls nothing" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        _gh_pr_reply_lane_available() { return 1; }
        gh() { return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT \
          | pr_reply_step6 1609 acme/widget '' newsha a.sh codex"
    assert_success
    assert_output --partial '전체 devx:pr-review-all 재실행 필요'
    run cat "$LANE_LOG"
    assert_output ''
}

@test "AC-5: an unavailable reviewer CLI never adds review-passed" {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_reply_lane_available() { return 1; }
    printf '%s\n' codex:BLOCKER:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' codex
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

# ---------------------------------------------------------------------
# NF-2 — gh:pr-reply may never self-certify
# ---------------------------------------------------------------------

@test "NF-2: a re-review that produced no verdict leaves the PR unlabelled" {
    STUB_VERDICT_codex=unknown
    run bash -c "STUB_VERDICT_codex=unknown
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        _gh_pr_reply_lane_available() { return 0; }
        gh() { printf 'gh %s\n' \"\$*\" >>'$GH_LOG'; return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha a.sh codex"
    assert_success
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

@test "NF-2: the lane is the only thing that can produce review-passed" {
    # No verdict source at all -> nothing may be certified.
    # shellcheck disable=SC2317  # called indirectly by the function under test
    pr_reply_targeted_rereview() { printf '\n'; }
    printf '%s\n' codex:BLOCKER:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' codex
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

# ---------------------------------------------------------------------
# Doc guards — the fixture is only trustworthy while the docs agree
# ---------------------------------------------------------------------

@test "doc-guard: targeted-rereview.md exists and names the gate functions" {
    run grep -qF -- '_gh_pr_reply_targeted_lane_decide' \
        "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_origin_line' \
        "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
    run grep -qF -- '_gh_pr_reply_targeted_lane_report' \
        "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
}

@test "doc-guard: targeted-rereview.md routes the label through the shared writer" {
    run grep -qF -- 'devx_pr_review_all_apply_label' \
        "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
}

@test "doc-guard: targeted-rereview.md scopes the re-call with --paths" {
    run grep -qF -- '--paths' "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
}

@test "doc-guard: targeted-rereview.md forbids the large-diff delegation path" {
    run grep -qF -- 'large-diff' "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
}

@test "doc-guard: targeted-rereview.md states NF-2 (never self-certify)" {
    run grep -qF -- 'NF-2' "${SKILL_DIR}/references/targeted-rereview.md"
    assert_success
}

# The whole issue: this exact expression is what pinned review-blocked on
# PR #1609. Its removal is the fix, so its return is the regression.
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

@test "doc-guard: the removal doc hands review-blocked to the targeted lane" {
    run grep -qF -- 'targeted-rereview.md' \
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

@test "doc-guard: the #1563 invalidation SSOT points at the per-reviewer gate" {
    run grep -qF -- '_gh_pr_reply_targeted_lane_decide' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
    assert_success
}

# devx:pr-review-all's reference doc is the label-lifecycle SSOT. Since #1616
# there is a second caller of the writer, and a reader who does not know that
# would conclude a review-passed on a gh:pr-reply pass was forged.
@test "doc-guard: the label-lifecycle SSOT names gh:pr-reply's targeted lane as a second producer" {
    local _producer="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/review-verdict-label.md"
    run grep -qF -- '#1616' "$_producer"
    assert_success
    run grep -qF -- 'gh:pr-reply' "$_producer"
    assert_success
}

@test "doc-guard: SKILL.md Step 3 records the per-reviewer origin token" {
    run grep -qF -- '<reviewer>:<severity>:<verdict>' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: SKILL.md Step 6 runs the targeted lane" {
    run grep -qF -- 'targeted-rereview.md' "${SKILL_DIR}/SKILL.md"
    assert_success
}

@test "doc-guard: final-summary.md reports the per-reviewer breakdown and the lane outcome" {
    run grep -qF -- '_gh_pr_reply_origin_tally' "${SKILL_DIR}/references/final-summary.md"
    assert_success
    run grep -qF -- '타겟 재검토' "${SKILL_DIR}/references/final-summary.md"
    assert_success
}

@test "doc-guard: constraints.md pins NF-2" {
    run grep -qF -- 'NF-2' "${SKILL_DIR}/references/constraints.md"
    assert_success
}

@test "doc-guard: gh:pr-review documents the --paths scope flag" {
    local _review_dir="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-review"
    run grep -qF -- '--paths' "${_review_dir}/SKILL.md"
    assert_success
    run grep -qF -- '--paths' "${_review_dir}/references/help.md"
    assert_success
}

@test "doc-guard: gh:pr-review says --paths stays on the inline path" {
    local _review_dir="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-review"
    run grep -qF -- '--paths' "${_review_dir}/SKILL.md"
    assert_success
    run grep -q 'inline' "${_review_dir}/SKILL.md"
    assert_success
}
