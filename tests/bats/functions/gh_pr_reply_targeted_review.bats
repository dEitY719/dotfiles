#!/usr/bin/env bats
# tests/bats/functions/gh_pr_reply_targeted_review.bats
# Issue #1616 — gh:pr-reply's per-reviewer/per-severity gate and the cheap
# targeted re-review lane that replaces the global
# `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0` rule.
#
# Incident this pins: PR #1609 — codex raised 2 BLOCKERs (both fixed), agy
# separately raised 3 non-blocking FOLLOW-UPs (all validly declined). The old
# global gate saw DECLINED_COUNT=3 and left `review-blocked` stuck, forcing a
# full 5-lane devx:pr-review-all re-run to clear one label.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# F-1 — every Step 3 item carries its origin: <reviewer>:<severity>:<verdict>
# ---------------------------------------------------------------------

@test "F-1: origin_line builds the canonical token" {
    run _gh_pr_reply_origin_line codex BLOCKER ACCEPT
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT'
}

@test "F-1: origin_line normalizes case and strips the reviewer's [brackets]" {
    run _gh_pr_reply_origin_line AGY '[Follow-Up]' decline
    assert_success
    assert_output 'agy:FOLLOW-UP:DECLINE'
}

@test "F-1: origin_line accepts ACCEPT-PARTIAL" {
    run _gh_pr_reply_origin_line codex '[BLOCKER]' accept-partial
    assert_success
    assert_output 'codex:BLOCKER:ACCEPT-PARTIAL'
}

@test "F-1: origin_line rejects an unknown reviewer (exit 2)" {
    run _gh_pr_reply_origin_line gemini BLOCKER ACCEPT
    assert_failure 2
}

@test "F-1: origin_line rejects an unknown verdict (exit 2)" {
    run _gh_pr_reply_origin_line codex BLOCKER MAYBE
    assert_failure 2
}

@test "F-1: origin_line rejects an empty severity (exit 2)" {
    run _gh_pr_reply_origin_line codex '' ACCEPT
    assert_failure 2
}

@test "F-1 (PR #1629 review, agy FOLLOW-UP): origin_line accepts the Korean 블로커 tag" {
    run _gh_pr_reply_origin_line codex '블로커' ACCEPT
    assert_success
    assert_output 'codex:블로커:ACCEPT'
}

@test "F-1 (PR #1629 review, agy FOLLOW-UP): severity_is_blocking recognizes the accepted 블로커 token round-trip" {
    run _gh_pr_reply_origin_line codex '블로커' ACCEPT
    assert_success
    run _gh_pr_reply_severity_is_blocking 블로커
    assert_success
}

@test "F-1: origin_line rejects a severity containing ':' (breaks the delimiter)" {
    run _gh_pr_reply_origin_line codex 'BLOCK:ER' ACCEPT
    assert_failure 2
}

@test "F-1: BLOCKER is the blocking severity" {
    run _gh_pr_reply_severity_is_blocking BLOCKER
    assert_success
}

@test "F-1: FOLLOW-UP / Suggestion / PRAISE are not blocking" {
    run _gh_pr_reply_severity_is_blocking FOLLOW-UP
    assert_failure
    run _gh_pr_reply_severity_is_blocking SUGGESTION
    assert_failure
    run _gh_pr_reply_severity_is_blocking PRAISE
    assert_failure
}

@test "F-1: tally breaks the pass down per reviewer, not as one flat count" {
    run bash -c "printf '%s\n' \
        codex:BLOCKER:ACCEPT \
        codex:BLOCKER:ACCEPT-PARTIAL \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE \
        | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_line 'reviewer=agy blocking_total=0 blocking_accepted=0 nonblocking_total=2 nonblocking_declined=2'
    assert_line 'reviewer=codex blocking_total=2 blocking_accepted=2 nonblocking_total=0 nonblocking_declined=0'
}

@test "F-1: tally ignores blank lines and reports nothing for empty input" {
    run bash -c "printf '\n\n' | { . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'; _gh_pr_reply_origin_tally; }"
    assert_success
    assert_output ''
}


# ---------------------------------------------------------------------
# F-2 — the `review-passed` gate (#1636)
# ---------------------------------------------------------------------
#
# #1616 asked "may we spend one scoped gh:pr-review re-call?" and needed the
# caller to name the reviewers that had blocked. #1636 removed the re-call, so
# the question collapsed to "did this pass leave an unresolved BLOCKER?" —
# answerable from ORIGINS alone.
#
# The relaxation is deliberate and is pinned here on purpose: these tests
# replace the old "no self-certification path exists" assertions, which
# described a rule the repo has since decided to trade away on this one path
# (cost + a repeatedly jammed gh:pr-merge-train). What is NOT relaxed — one
# unresolved BLOCKER means no label — has its own tests below.

_gate() {
    printf '%s\n' "$1" | _gh_pr_reply_review_passed_gate
}

@test "F-2 (#1636): every BLOCKER accepted -> pass, with the count" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:ACCEPT
agy:FOLLOW-UP:DECLINE'
    assert_success
    assert_output 'pass=blockers-resolved:2'
}

@test "F-2 (#1636): no BLOCKER item at all -> pass" {
    # The ordinary clean-PR shape. Under #1616 this read as unresolved,
    # because the caller had already asserted somebody blocked; with no such
    # assertion, holding here would leave every clean PR unlabelled forever.
    run _gate 'agy:FOLLOW-UP:DECLINE
agy:Suggestion:ACCEPT'
    assert_success
    assert_output 'pass=no-blocker'
}

@test "F-2 (#1636): an empty stream is a pass, not an error" {
    run _gate ''
    assert_success
    assert_output 'pass=no-blocker'
}

@test "F-2 (#1636): ACCEPT-PARTIAL counts as resolved" {
    run _gate 'codex:BLOCKER:ACCEPT-PARTIAL'
    assert_success
    assert_output 'pass=blockers-resolved:1'
}

# ---------------------------------------------------------------------
# The fail-closed half — NOT relaxed by #1636
# ---------------------------------------------------------------------

@test "F-2 (fail-closed): a DECLINEd BLOCKER holds the label" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:DECLINE
agy:FOLLOW-UP:ACCEPT'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): a QUESTION on a BLOCKER is not a resolution" {
    run _gate 'codex:BLOCKER:ACCEPT
codex:BLOCKER:QUESTION'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): one unresolved BLOCKER outranks every resolved one" {
    run _gate 'codex:BLOCKER:ACCEPT
agy:BLOCKER:DECLINE'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "F-2 (fail-closed): the Korean 블로커 tag blocks too" {
    # `_gh_pr_reply_severity_is_blocking` recognizes it even though the
    # tally's awk only groups the ASCII spellings — counting MORE items as
    # blocking is the safe direction for a gate that authorizes review-passed.
    run _gate 'codex:블로커:DECLINE'
    assert_success
    assert_output 'hold=unresolved-blocker:codex'
}

@test "F-2 (fail-closed): a BLOCKING-spelled severity blocks too" {
    run _gate 'agy:BLOCKING:QUESTION'
    assert_success
    assert_output 'hold=unresolved-blocker:agy'
}

@test "F-2: a malformed origin line is rejected (exit 2), never silently dropped" {
    run _gate 'codex:BLOCKER'
    assert_failure 2
}

# ---------------------------------------------------------------------
# Reporting the outcome (Step 7)
# ---------------------------------------------------------------------

@test "report (#1636): a resolved-BLOCKER pass names the count and the label flip" {
    run _gh_pr_reply_review_passed_report pass=blockers-resolved:2
    assert_success
    assert_output --partial 'BLOCKER 2건 전부 해소'
    assert_output --partial 'review-blocked 해제'
    assert_output --partial 'review-passed'
}

@test "report (#1636): the pass line says no external re-review was involved" {
    # The relaxation must be visible in the run's own output, not only in the
    # docs — a reader of the summary should see how the label was earned.
    run _gh_pr_reply_review_passed_report pass=no-blocker
    assert_success
    assert_output --partial '외부 재검토 없음'
    assert_output --partial '#1636'
}

@test "report: the hold line names the reviewer and never claims a pass" {
    run _gh_pr_reply_review_passed_report hold=unresolved-blocker:codex
    assert_success
    assert_output --partial 'codex'
    assert_output --partial 'review-blocked 유지'
    assert_output --partial 'review-passed 미부여'
}

@test "report rejects a token it does not understand (exit 2)" {
    run _gh_pr_reply_review_passed_report lane=codex
    assert_failure 2
}

# ---------------------------------------------------------------------
# _gh_pr_reply_apply_review_passed — the gate wired to the shared writer
# ---------------------------------------------------------------------

_apply_stub() {
    APPLY_LOG="${BATS_TEST_TMPDIR}/apply.log"
    : >"$APPLY_LOG"
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$APPLY_LOG"
        return "${STUB_GH_RC:-0}"
    }
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    _gh_pr_edit_safe_label() {
        printf 'add %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$APPLY_LOG"
        return "${STUB_ADD_RC:-0}"
    }
}

@test "apply (#1636): a clean pass applies review-passed with no CLI re-call" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget ghe.example.com newsha \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output --partial 'add 1609 review-passed --repo acme/widget'
    # Not one reviewer CLI, and not gh:pr-review, is invoked anywhere.
    refute_output --partial '--ai '
    refute_output --partial '--paths'
    refute_output --partial 'pr-review'
}

@test "apply (#1636): applying review-passed deletes review-blocked first" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "apply (#1636, NF-1): the label carries the post-push head sha as its marker" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha >/dev/null
    run cat "$APPLY_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "apply: every gh call pins the target host (#1403 / #1407)" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:ACCEPT |
        _gh_pr_reply_apply_review_passed 1609 acme/widget ghe.example.com newsha >/dev/null
    run grep -c 'GH_HOST=ghe.example.com' "$APPLY_LOG"
    assert_success
    refute_output '0'
}

@test "apply (#1636): a PR with no BLOCKER at all still earns the label" {
    _apply_stub
    printf '%s\n' agy:FOLLOW-UP:DECLINE |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output --partial 'add 1609 review-passed'
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'BLOCKER 항목 자체가 없음'
}

@test "apply (fail-closed): an unresolved BLOCKER writes nothing at all" {
    _apply_stub
    printf '%s\n' codex:BLOCKER:DECLINE |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha \
            >"${BATS_TEST_TMPDIR}/out"
    run cat "$APPLY_LOG"
    assert_output ''
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial 'review-passed 미부여'
    assert_output --partial 'review-blocked 유지'
}

@test "apply (fail-closed): an unresolved BLOCKER never touches review-blocked" {
    # The hold path must not delete the opposite label either — that delete
    # only happens on the write path, which this input never reaches.
    _apply_stub
    printf '%s\n' codex:BLOCKER:QUESTION |
        _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha >/dev/null
    run cat "$APPLY_LOG"
    refute_output --partial 'labels/review-blocked'
}

@test "apply: a label the repo lacks warns and leaves the PR unlabelled (soft-fail)" {
    _apply_stub
    STUB_ADD_RC=3
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 3; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget
    "
    unset STUB_ADD_RC
    assert_success
    assert_output --partial 'gh:label-bootstrap'
    refute_output --partial '[OK]'
}

@test "apply: any other write failure warns instead of claiming the label" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 1; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget
    "
    assert_success
    assert_output --partial '미검증으로 취급'
}

@test "apply: a marker-post failure adds a second WARN, not silence (#1608 rule)" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh'
        gh() { return 1; }
        _gh_pr_edit_safe_label() { return 0; }
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609 acme/widget '' newsha
    "
    assert_success
    assert_line --index 1 --partial 'freshness marker failed to post'
}

@test "apply: a missing repo arg is a usage error (rc 2)" {
    run bash -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh'
        printf 'codex:BLOCKER:ACCEPT\n' | _gh_pr_reply_apply_review_passed 1609
    "
    assert_failure 2
    assert_output --partial 'usage: _gh_pr_reply_apply_review_passed'
}

# ---------------------------------------------------------------------
# The #1616 re-review lane is gone (#1636 F-3)
# ---------------------------------------------------------------------

@test "#1636: the targeted re-review lane's functions no longer exist" {
    # Leaving them defined would be a maintenance trap: nothing consumes a
    # `lane=` token any more, and a future caller finding one would rebuild
    # the very CLI round-trip this issue removed.
    for _fn in _gh_pr_reply_targeted_lane_decide _gh_pr_reply_lane_available \
        _gh_pr_reply_targeted_lane_report; do
        run command -v "$_fn"
        assert_failure
    done
}

# The library's prose still *describes* the removed lane (that history is why
# the relaxation is legible), so these guards read CODE only — comment lines
# stripped — or they would pin the documentation instead of the behaviour.
_lib_code_file() {
    local _lib="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh"
    LIB_CODE="${BATS_TEST_TMPDIR}/lib_code.sh"
    grep -v '^[[:space:]]*#' "$_lib" >"$LIB_CODE"
}

@test "#1636: the library's code no longer re-invokes any reviewer CLI" {
    _lib_code_file
    run grep -qF -- '_gh_pr_review_require_ai_cli' "$LIB_CODE"
    assert_failure
    run grep -qF -- '--paths' "$LIB_CODE"
    assert_failure
    run grep -qF -- 'gh_pr_review.sh' "$LIB_CODE"
    assert_failure
}

@test "#1636: the library never fabricates a reviewer verdict token" {
    # The one banned shortcut: synthesizing an `lgtm`/`concerns` line and
    # feeding it to devx_pr_review_all_apply_label would record gh:pr-reply's
    # own judgment as a reviewer CLI's opinion. It writes a LABEL directly.
    _lib_code_file
    run grep -qF -- 'devx_pr_review_all_apply_label' "$LIB_CODE"
    assert_failure
    run grep -qE "printf.*'(lgtm|concerns)" "$LIB_CODE"
    assert_failure
    run grep -qF -- 'devx_pr_review_all_write_label' "$LIB_CODE"
    assert_success
}

# ---------------------------------------------------------------------
# Library hygiene
# ---------------------------------------------------------------------

@test "the library defines every function the skill delegates to" {
    for _fn in _gh_pr_reply_origin_line _gh_pr_reply_severity_is_blocking \
        _gh_pr_reply_origin_tally _gh_pr_reply_review_passed_gate \
        _gh_pr_reply_review_passed_report _gh_pr_reply_apply_review_passed; do
        run command -v "$_fn"
        assert_success
    done
}

@test "the library loads in a non-interactive shell with no interactive guard" {
    # The skill's Bash tool calls run `bash --noprofile --norc`; an
    # interactive guard here would silently define nothing and the gate
    # would never run (#724's failure shape).
    run bash --noprofile --norc -c \
        ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh' && command -v _gh_pr_reply_review_passed_gate"
    assert_success
}
