#!/usr/bin/env bats
# tests/bats/functions/gh_pr_reply_targeted_review_passed_gate.bats
# Issue #1636 — the shell SSOT half of gh-pr:reply Step 6's `review-passed`
# gate: the invalidation SSOT's doc in shell-common/lib/gh_pr_edit_safe.sh
# and the evidence probe _gh_pr_reply_history_has_review in
# shell-common/lib/gh_pr_reply_targeted_review.sh.
# Fixture: _fixtures/gh_pr_reply_targeted_review_passed_gate.sh (sources them).
#
# #2200: the end-to-end Step 6 tests (AC-1..AC-5, the PR #1637 cross-pass /
# evidence / ledger holes, #1639 authorship through Step 6) exercised the
# skill's own ordering, so they moved with that text to the gh-pr-skills repo
# (tests/bats/gh_pr_reply_targeted_review_passed_gate.bats), where they run the
# shipped skills/reply/references/review-passed-gate.md blocks.

load '../test_helper'

FIXTURE='tests/bats/functions/_fixtures/gh_pr_reply_targeted_review_passed_gate.sh'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------
# Doc guards — the #1563 invalidation SSOT
# ---------------------------------------------------------------------

@test "doc-guard: the #1563 invalidation SSOT no longer states the global counter rule" {
    run grep -qE 'ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_edit_safe.sh"
    assert_failure
}

@test "doc-guard: the #1563 invalidation SSOT points at the current gate" {
    run grep -qF -- '_gh_pr_reply_review_passed_gate' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_edit_safe.sh"
    assert_success
}

@test "doc-guard: the #1563 invalidation SSOT records the NF-2 relaxation" {
    run grep -qF -- '#1636' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_edit_safe.sh"
    assert_success
    run grep -q 'RELAXED' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_edit_safe.sh"
    assert_success
}

# ---------------------------------------------------------------------------
# PR #1703 self-record review, BLOCKER 3 — evidence freshness on the
# ORIGINS-empty path (`gh:pr-reply` Step 2.5).
# ---------------------------------------------------------------------------

@test "has_review (PR #1703 review): a marker for a DIFFERENT head is not evidence for this head" {
    # Step 2.5 runs the gate with ORIGINS empty by construction, so history is
    # the ONLY evidence. Before the fix the probe matched `<!-- ai-review:`
    # with no sha comparison at all, so a PR reviewed at sha A and then pushed
    # to sha B — with every comment already answered, which is exactly what
    # sends the pass down the Step 2.5 path — got `review-passed` stamped for
    # a head no reviewer had ever seen.
    local _stale=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local _head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local _login=dEitY719
    local _json="${BATS_TEST_TMPDIR}/bodies.json"
    local _fn="${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_reply_targeted_review.sh"
    jq -nc --arg l "$_login" --arg s "$_stale" \
        '[{user: {login: $l}, body: ("<!-- ai-review:codex:" + $s + " -->")}]' >"$_json"

    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_head' <'$_json'"
    assert_failure

    # The same marker IS evidence for its own head.
    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_stale' <'$_json'"
    assert_success

    # Omitting the sha keeps the pre-existing behaviour for Step 6, which
    # carries its own fresh ORIGINS and does not need this stricter probe.
    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' <'$_json'"
    assert_success

    # A marker from ANOTHER commenter is never evidence, sha or not (#1639).
    jq -nc --arg s "$_head" \
        '[{user: {login: "someone-else"}, body: ("<!-- ai-review:codex:" + $s + " -->")}]' >"$_json"
    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_head' <'$_json'"
    assert_failure
}

# ---------------------------------------------------------------------------
# gh-verify-skills#56 — the marker grew an optional `<preset>` field, and this
# probe is one of its three readers. Reading only the 2-field form would make
# a PR reviewed solely by a non-default lane (say `opencode:thorough`) look
# like a PR no external reviewer ever touched — the gate would then withhold
# `review-passed` forever on exactly the fan-outs #56 exists to enable.
# ---------------------------------------------------------------------------

@test "has_review (#56): a preset-tagged marker is evidence for its head" {
    local _head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local _stale=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local _login=dEitY719
    local _json="${BATS_TEST_TMPDIR}/bodies.json"
    local _fn="${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_reply_targeted_review.sh"
    jq -nc --arg l "$_login" --arg s "$_head" \
        '[{user: {login: $l}, body: ("<!-- ai-review:opencode:thorough:" + $s + " -->")}]' >"$_json"

    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_head' <'$_json'"
    assert_success

    # Freshness still gates it — the preset field must not become a way in for
    # a stale review.
    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_stale' <'$_json'"
    assert_failure

    # And authorship still gates it (#1639).
    jq -nc --arg s "$_head" \
        '[{user: {login: "someone-else"}, body: ("<!-- ai-review:opencode:thorough:" + $s + " -->")}]' >"$_json"
    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_head' <'$_json'"
    assert_failure
}

@test "has_review (#56): a sha alone cannot be satisfied by unrelated prose" {
    # The relaxed pattern still anchors on the marker and forbids spaces in
    # the reviewer/preset fields, so a comment merely MENTIONING the sha is
    # not evidence.
    local _head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local _login=dEitY719
    local _json="${BATS_TEST_TMPDIR}/bodies.json"
    local _fn="${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/gh_pr_reply_targeted_review.sh"
    jq -nc --arg l "$_login" --arg s "$_head" \
        '[{user: {login: $l}, body: ("<!-- ai-review: not a marker " + $s + " -->")}]' >"$_json"

    run bash -c "DOTFILES_FORCE_INIT=1 . '$_fn'; _gh_pr_reply_history_has_review '$_login' '$_head' <'$_json'"
    assert_failure
}
