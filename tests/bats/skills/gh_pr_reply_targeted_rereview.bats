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
#
# Issue #1634 then made `review-blocked` removal UNCONDITIONAL — Step 5's
# "reply to every comment" contract is its only precondition. The targeted
# lane survives, but only when `PUSHED_FIXES > 0` and only as an opportunistic
# `review-passed` upgrade; a lane verdict that comes back BLOCKING re-applies
# `review-blocked` on that fresh, independent evidence (still not NF-2
# self-certification). The AC-3 / AC-4 rows above are re-read in that light:
# what the lane still governs is `review-passed`, not `review-blocked`.

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
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh b.sh' 1 codex
    run cat "$LANE_LOG"
    assert_output --partial 'gh:pr-review --ai codex'
}

@test "AC-1: the targeted call is scoped to the fix commit's files only" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh b.sh' 1 codex
    run cat "$LANE_LOG"
    assert_output --partial '--paths a.sh b.sh'
}

@test "AC-2: a non-blocking re-review applies review-passed" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial 'pr edit 1609 --repo acme/widget --add-label review-passed'
}

@test "AC-2: applying review-passed deletes review-blocked first" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "AC-2: only the ONE targeted lane runs — no devx:pr-review-all fan-out" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
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
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "AC-2: every gh call pins the target host (#1403 / #1407)" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run grep -c 'GH_HOST=ghe.example.com' "$GH_LOG"
    assert_success
    refute_output '0'
}

@test "AC-2: CONCERNS is non-blocking too" {
    STUB_VERDICT_codex=concerns
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial '--add-label review-passed'
}

# ---------------------------------------------------------------------
# AC-3 — still blocking
# ---------------------------------------------------------------------

@test "AC-3: a still-blocking re-review keeps review-blocked" {
    STUB_VERDICT_codex=blocking
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 'a.sh' 1 codex
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
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha a.sh 1 codex"
    assert_success
    assert_output --partial '타겟 재검토도 여전히 BLOCKING — 재수정 필요'
}

# ---------------------------------------------------------------------
# AC-4 — an unresolved blocker never spends an API call
# ---------------------------------------------------------------------

# Since #1634 the lane's silence no longer means the label survives: the
# unconditional drop already happened above it. What AC-4 still buys is the
# API call the lane does not spend, and the `review-passed` it never earns.
@test "AC-4: a DECLINEd BLOCKER never calls the targeted lane" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}'
        _gh_pr_reply_lane_available() { return 0; }
        gh() { printf 'gh %s\n' \"\$*\" >>'$GH_LOG'; return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE \
          | pr_reply_step6 1609 acme/widget '' newsha a.sh 1 codex"
    assert_success
    assert_output --partial '타겟 재검토 미실행'
    run cat "$LANE_LOG"
    assert_output ''
}

# #1634: the same shape that used to pin the label. The lane is still skipped
# (above), but the drop is not the lane's job any more.
@test "AC-4 (#1634): a DECLINEd BLOCKER still drops review-blocked" {
    printf '%s\n' codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
    run cat "$LANE_LOG"
    assert_output ''
}

@test "AC-4: an unresolved blocker never adds review-passed" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

@test "AC-4: review-passed is still invalidated on every push (unchanged rule)" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-passed'
}

# ---------------------------------------------------------------------
# Issue #1634 — review-blocked removal is unconditional
#
# Step 5's "reply to every comment" contract is the whole precondition. The
# gate the lane still applies governs `review-passed` only.
# ---------------------------------------------------------------------

# The PR #1630 shape: every item was answered, all of them DECLINEd with
# justification, so nothing was pushed. Under #1616 that pinned the label
# with no way out but a full 5-lane re-run.
@test "#1634: review-blocked drops with no push at all (the PR #1630 shape)" {
    printf '%s\n' codex:BLOCKER:DECLINE agy:FOLLOW-UP:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha '' 0 codex
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
    assert_output --partial 'GH_HOST=ghe.example.com'
}

# The asymmetry: `review-passed` still needs a new head to have expired.
@test "#1634: no push leaves review-passed untouched" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha '' 0 codex
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    refute_output --partial '--add-label'
}

# Even a fully resolved blocker set earns nothing without a push: there is no
# new head for an independent re-review to certify (NF-1 / NF-2).
@test "#1634: with no push the targeted lane never runs" {
    STUB_VERDICT_codex=lgtm
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 0 codex
    run cat "$LANE_LOG"
    assert_output ''
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

# The drop is not "kept": it happens, and only a fresh BLOCKING verdict from
# the independent re-review puts the label back. Order proves the difference.
@test "#1634: a still-blocking re-review re-applies review-blocked on fresh evidence" {
    local _drop _add
    STUB_VERDICT_codex=blocking
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 'a.sh' 1 codex
    _drop=$(grep -n 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked' \
        "$GH_LOG" | head -n 1 | cut -d: -f1)
    _add=$(grep -n -- '--add-label review-blocked' "$GH_LOG" | head -n 1 | cut -d: -f1)
    [ -n "$_drop" ]
    [ -n "$_add" ]
    [ "$_drop" -lt "$_add" ]
}

# The rule the global ACCEPTED/DECLINED counters used to encode is gone in
# both directions: no verdict mix may hold the label down.
@test "#1634: the review-blocked drop ignores the ACCEPT/DECLINE ratio" {
    local _shape
    for _shape in codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE agy:FOLLOW-UP:DECLINE; do
        : >"$GH_LOG"
        printf '%s\n' "$_shape" |
            pr_reply_step6 1609 acme/widget ghe.example.com newsha '' 0 codex
        run grep -c 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked' "$GH_LOG"
        assert_success
        assert_output '1'
    done
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
          | pr_reply_step6 1609 acme/widget '' newsha a.sh 1 codex"
    assert_success
    assert_output --partial '전체 devx:pr-review-all 재실행 필요'
    run cat "$LANE_LOG"
    assert_output ''
}

@test "AC-5: an unavailable reviewer CLI never adds review-passed" {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_reply_lane_available() { return 1; }
    printf '%s\n' codex:BLOCKER:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' 1 codex
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
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha a.sh 1 codex"
    assert_success
    run cat "$GH_LOG"
    refute_output --partial '--add-label review-passed'
}

@test "NF-2: the lane is the only thing that can produce review-passed" {
    # No verdict source at all -> nothing may be certified.
    # shellcheck disable=SC2317  # called indirectly by the function under test
    pr_reply_targeted_rereview() { printf '\n'; }
    printf '%s\n' codex:BLOCKER:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 'a.sh' 1 codex
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

@test "doc-guard: the removal doc still routes the DECISION token to the lane doc" {
    run grep -qF -- 'targeted-rereview.md' \
        "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_success
}

# The #1634 fix itself, read off the doc's own bash block rather than its
# prose: `review-blocked` must be dropped BEFORE the `PUSHED_FIXES` gate is
# even mentioned, and `review-passed` after it. Putting the review-blocked
# drop back inside that gate is the regression this guards.
_removal_code_block() {
    awk '/^```bash/ { inb = 1; next } /^```/ { if (inb) exit } inb { print }' \
        "${SKILL_DIR}/references/verdict-label-removal.sh.md"
}

@test "doc-guard: the removal doc drops review-blocked before the PUSHED_FIXES gate" {
    local _code _blocked _gate
    _code="${BATS_TEST_TMPDIR}/removal-block.sh"
    _removal_code_block >"$_code"
    _blocked=$(grep -n '_gh_pr_drop_label.*review-blocked' "$_code" | head -n 1 | cut -d: -f1)
    _gate=$(grep -n 'PUSHED_FIXES' "$_code" | head -n 1 | cut -d: -f1)
    [ -n "$_blocked" ]
    [ -n "$_gate" ]
    [ "$_blocked" -lt "$_gate" ]
}

@test "doc-guard: the removal doc keeps review-passed inside the PUSHED_FIXES gate" {
    local _code _passed _gate
    _code="${BATS_TEST_TMPDIR}/removal-block.sh"
    _removal_code_block >"$_code"
    _passed=$(grep -n '_gh_pr_drop_label.*review-passed' "$_code" | head -n 1 | cut -d: -f1)
    _gate=$(grep -n 'PUSHED_FIXES' "$_code" | head -n 1 | cut -d: -f1)
    [ -n "$_passed" ]
    [ -n "$_gate" ]
    [ "$_gate" -lt "$_passed" ]
}

# The lane is now an upgrade path, so it too must sit behind the push gate —
# a re-review before the fixes exist would certify the wrong head (NF-1).
@test "doc-guard: the removal doc runs the lane only after the PUSHED_FIXES gate" {
    local _code _lane _gate
    _code="${BATS_TEST_TMPDIR}/removal-block.sh"
    _removal_code_block >"$_code"
    _lane=$(grep -n '_gh_pr_reply_targeted_lane_decide' "$_code" | head -n 1 | cut -d: -f1)
    _gate=$(grep -n 'PUSHED_FIXES' "$_code" | head -n 1 | cut -d: -f1)
    [ -n "$_lane" ]
    [ -n "$_gate" ]
    [ "$_gate" -lt "$_lane" ]
}

# #1616's per-reviewer gate replaced the global counter; #1634 took it off
# `review-blocked` entirely. Naming the issue keeps the reader from reading
# the surviving lane as the removal condition.
@test "doc-guard: the removal doc names #1634 as the unconditional-drop rule" {
    run grep -qF -- '#1634' "${SKILL_DIR}/references/verdict-label-removal.sh.md"
    assert_success
    run grep -qF -- '#1634' "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_edit_safe.sh"
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
