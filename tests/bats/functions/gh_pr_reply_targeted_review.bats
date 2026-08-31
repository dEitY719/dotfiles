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
# F-2 / F-6 — the per-reviewer gate
# ---------------------------------------------------------------------

# Every decide test runs the origin stream through stdin, exactly as the
# skill does, and stubs the CLI-availability probe so the decision under test
# is the gate and not the machine this suite happens to run on.
_decide() {
    local _origins="$1"
    shift
    printf '%s\n' "$_origins" | _gh_pr_reply_targeted_lane_decide "$@"
}

_stub_lane_available() {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_reply_lane_available() { return 0; }
}

_stub_lane_unavailable() {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_reply_lane_available() { return 1; }
}

@test "F-2 (AC-1): blocking reviewer fully ACCEPTed + another reviewer's DECLINE -> lane runs" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT
codex:BLOCKER:ACCEPT
agy:FOLLOW-UP:DECLINE
agy:FOLLOW-UP:DECLINE
agy:FOLLOW-UP:DECLINE' codex
    assert_success
    assert_output 'lane=codex'
}

@test "F-2: ACCEPT-PARTIAL counts as resolved for the blocking gate" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT-PARTIAL' codex
    assert_success
    assert_output 'lane=codex'
}

@test "F-2: a QUESTION on a blocking item is not a resolution" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT
codex:BLOCKER:QUESTION' codex
    assert_success
    assert_output 'skip=unresolved-blocker:codex'
}

@test "F-6 (AC-4): a DECLINEd blocking item keeps the label and never calls the lane" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT
codex:BLOCKER:DECLINE
agy:FOLLOW-UP:ACCEPT' codex
    assert_success
    assert_output 'skip=unresolved-blocker:codex'
}

@test "F-6: one unresolved blocking reviewer suppresses the lane for the resolved one too" {
    # Re-reviewing codex cannot clear a label agy is still holding down, so
    # the cheapest correct answer is no API call at all.
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT
agy:BLOCKER:DECLINE' codex agy
    assert_success
    assert_output 'skip=unresolved-blocker:agy'
}

@test "F-2: two blocking reviewers both fully resolved -> both lanes run" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT
agy:BLOCKER:ACCEPT-PARTIAL' codex agy
    assert_success
    assert_output 'lane=codex agy'
}

@test "F-2: a blocking reviewer with no item in this pass is unresolved, not vacuously clear" {
    # Nothing in this pass proves that reviewer's blocker was addressed, and
    # "no evidence" must never read as "resolved" (NF-2's direction).
    _stub_lane_available
    run _decide 'agy:FOLLOW-UP:ACCEPT' codex
    assert_success
    assert_output 'skip=unresolved-blocker:codex'
}

@test "F-2: no originally-blocking reviewer -> nothing to re-verify" {
    _stub_lane_available
    run _decide 'agy:FOLLOW-UP:DECLINE'
    assert_success
    assert_output 'skip=no-blocking-reviewer'
}

@test "F-2: an unknown reviewer name is rejected (exit 2), never silently dropped" {
    _stub_lane_available
    run _decide 'codex:BLOCKER:ACCEPT' gemini
    assert_failure 2
}

# ---------------------------------------------------------------------
# F-7 — CLI gone / wrong environment falls back to the pre-#1616 behavior
# ---------------------------------------------------------------------

@test "F-7 (AC-5): a blocking reviewer whose CLI is unavailable skips the lane" {
    _stub_lane_unavailable
    run _decide 'codex:BLOCKER:ACCEPT' codex
    assert_success
    assert_output 'skip=cli-unavailable:codex'
}

@test "F-7: an unresolved blocker outranks CLI availability (no probe needed)" {
    _stub_lane_unavailable
    run _decide 'codex:BLOCKER:DECLINE' codex
    assert_success
    assert_output 'skip=unresolved-blocker:codex'
}

@test "F-7: lane_available delegates to gh:pr-review's own CLI gate" {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_review_require_ai_cli() {
        printf '%s\n' "$1" >"${BATS_TEST_TMPDIR}/probed"
        return 0
    }
    run _gh_pr_reply_lane_available codex
    assert_success
    run cat "${BATS_TEST_TMPDIR}/probed"
    assert_output 'codex'
}

@test "F-7: lane_available reports unavailable when the shared gate refuses" {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_review_require_ai_cli() { return 1; }
    run _gh_pr_reply_lane_available hermes
    assert_failure
}

@test "F-7: lane_available never leaks the CLI gate's stderr into the report" {
    # shellcheck disable=SC2317  # called indirectly by the function under test
    _gh_pr_review_require_ai_cli() {
        printf 'Required CLI %s not found in PATH\n' "$1" >&2
        return 1
    }
    run _gh_pr_reply_lane_available opencode
    assert_failure
    assert_output ''
}

# ---------------------------------------------------------------------
# F-4 / F-5 — reporting the outcome (Step 7)
# ---------------------------------------------------------------------

@test "F-5 (AC-3): a still-blocking re-review says so explicitly" {
    run _gh_pr_reply_targeted_lane_report verdict=blocking
    assert_success
    assert_output --partial '타겟 재검토도 여전히 BLOCKING — 재수정 필요'
}

@test "F-4 (AC-2): an LGTM re-review reports the label flip" {
    run _gh_pr_reply_targeted_lane_report verdict=lgtm
    assert_success
    assert_output --partial 'review-blocked 해제'
    assert_output --partial 'review-passed'
}

@test "F-4: CONCERNS is non-blocking and reports the same flip" {
    run _gh_pr_reply_targeted_lane_report verdict=concerns
    assert_success
    assert_output --partial 'review-blocked 해제'
}

@test "F-4 (NF-2): an unknown verdict never claims a pass" {
    run _gh_pr_reply_targeted_lane_report verdict=unknown
    assert_success
    refute_output --partial 'review-passed'
    assert_output --partial '전체 devx:pr-review-all 재실행 필요'
}

@test "F-6: the unresolved-blocker skip reports the reviewer by name" {
    run _gh_pr_reply_targeted_lane_report skip=unresolved-blocker:codex
    assert_success
    assert_output --partial 'codex'
    assert_output --partial 'review-blocked 유지'
    refute_output --partial 'review-passed'
}

@test "F-7 (AC-5): the cli-unavailable skip asks for the full re-run" {
    run _gh_pr_reply_targeted_lane_report skip=cli-unavailable:hermes
    assert_success
    assert_output --partial 'hermes'
    assert_output --partial '전체 devx:pr-review-all 재실행 필요'
}

@test "F-2: the no-blocking-reviewer skip is not an error" {
    run _gh_pr_reply_targeted_lane_report skip=no-blocking-reviewer
    assert_success
    refute_output --partial 'review-passed'
}

@test "report rejects a token it does not understand (exit 2)" {
    run _gh_pr_reply_targeted_lane_report lane=codex
    assert_failure 2
}

# ---------------------------------------------------------------------
# Library hygiene
# ---------------------------------------------------------------------

@test "the library defines every function the skill delegates to" {
    for _fn in _gh_pr_reply_origin_line _gh_pr_reply_severity_is_blocking \
        _gh_pr_reply_origin_tally _gh_pr_reply_targeted_lane_decide \
        _gh_pr_reply_lane_available _gh_pr_reply_targeted_lane_report; do
        run command -v "$_fn"
        assert_success
    done
}

@test "the library loads in a non-interactive shell with no interactive guard" {
    # The skill's Bash tool calls run `bash --noprofile --norc`; an
    # interactive guard here would silently define nothing and the gate
    # would never run (#724's failure shape).
    run bash --noprofile --norc -c \
        ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_reply_targeted_review.sh' && command -v _gh_pr_reply_targeted_lane_decide"
    assert_success
}
