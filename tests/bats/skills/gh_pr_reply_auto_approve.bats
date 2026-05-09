#!/usr/bin/env bats
# tests/bats/skills/gh_pr_reply_auto_approve.bats
# Verify the Step 8 solo-repo auto-approve gate documented in
#   claude/skills/gh-pr-reply/SKILL.md
#   claude/skills/gh-pr-reply/references/auto-approve.md
# Source-of-truth fixture: _fixtures/gh_pr_reply_auto_approve.sh.
#
# Seven cases drawn from issue #410's acceptance criteria:
#   1. allowlist match, all guards pass            → helper called + bypass=1 + audit
#   2. allowlist set, repo NOT in allowlist        → no-op + skip info
#   3. env unset                                   → silent no-op
#   4. allowlist match, isDraft=true               → skip + draft info
#   5. allowlist match, reviewDecision=CHANGES_REQUESTED → skip + decision info
#   6. comment count = 0 (defensive guard)         → silent no-op
#   7. helper returns 2 (transient/fail-closed)    → audit + helper-rc warn, rc=0

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_HELPER_LOG="$(mktemp)"
    export FAKE_HELPER_LOG
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_reply_auto_approve.sh"
}

teardown() {
    teardown_isolated_home
    [ -n "$FAKE_HELPER_LOG" ] && rm -f "$FAKE_HELPER_LOG"
    unset FAKE_HELPER_LOG FAKE_HELPER_RC \
          GH_PR_REPLY_AUTO_APPROVE_REPOS \
          _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
}

@test "auto-approve: allowlist match + all guards pass → helper called with bypass=1" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    assert_output --partial 'auto-approve: solo-repo allowlist match'
    assert_output --partial 'bypassing #393 fail-closed guard for PR #42'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
    assert_output --partial 'args=pr 42 Approved --only-from In review'
}

@test "auto-approve: bypass env var does NOT leak to caller scope" {
    # The prefix form `_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 helper`
    # must scope the binding to that single call. Verify the caller's
    # shell sees the variable unset after the function returns.
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    unset _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
    gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED" >/dev/null 2>&1
    [ -z "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-}" ]
}

@test "auto-approve: repo NOT in allowlist → no helper call + info line" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "Anthropic/AgentToolbox" 3 "OPEN" "false" "APPROVED"
    assert_success
    assert_output --partial 'Anthropic/AgentToolbox not in allowlist'
    refute_output --partial 'bypassing'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: env var unset → silent no-op" {
    unset GH_PR_REPLY_AUTO_APPROVE_REPOS
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    refute_output --partial 'auto-approve'
    refute_output --partial 'allowlist'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: env var empty string → silent no-op" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS=""
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    refute_output --partial 'auto-approve'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: isDraft=true → skip + draft info" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "true" "APPROVED"
    assert_success
    assert_output --partial 'PR #42 is a draft'
    refute_output --partial 'bypassing'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: state != OPEN → skip + state info" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "MERGED" "false" "APPROVED"
    assert_success
    assert_output --partial 'state=MERGED'
    assert_output --partial 'need OPEN'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: reviewDecision=CHANGES_REQUESTED → skip + decision info" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "CHANGES_REQUESTED"
    assert_success
    assert_output --partial 'reviewDecision=CHANGES_REQUESTED'
    assert_output --partial 'need null|APPROVED'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: reviewDecision=REVIEW_REQUIRED → skip" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "REVIEW_REQUIRED"
    assert_success
    assert_output --partial 'reviewDecision=REVIEW_REQUIRED'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: reviewDecision=null → passes G4 (no reviews yet)" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "null"
    assert_success
    assert_output --partial 'bypassing'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
}

@test "auto-approve: reviewDecision empty string → passes G4 (no reviews yet)" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" ""
    assert_success
    assert_output --partial 'bypassing'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
}

@test "auto-approve: comment_count=0 → silent no-op (defensive G2)" {
    # SKILL.md guarantees Step 8 unreachable when Step 2.5 early-exits,
    # but the gate function itself must also no-op silently if called
    # with COMMENT_COUNT=0 (belt-and-braces).
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 0 "OPEN" "false" "APPROVED"
    assert_success
    refute_output --partial 'auto-approve'
    refute_output --partial 'allowlist'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "auto-approve: helper returns 2 → audit + helper-rc warn, rc=0 soft-fail" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    FAKE_HELPER_RC=2
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    assert_output --partial 'bypassing'
    assert_output --partial 'helper rc=2'
    assert_output --partial 'continuing (soft-fail)'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
}

@test "auto-approve: multi-repo allowlist matches second entry" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="foo/bar,dEitY719/dotfiles,baz/qux"
    run gh_pr_reply_auto_approve_step8 \
        42 "dEitY719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    assert_output --partial 'bypassing'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
}

@test "auto-approve: case-exact match required (lowercase repo misses uppercase allowlist entry)" {
    GH_PR_REPLY_AUTO_APPROVE_REPOS="dEitY719/dotfiles"
    run gh_pr_reply_auto_approve_step8 \
        42 "deity719/dotfiles" 3 "OPEN" "false" "APPROVED"
    assert_success
    assert_output --partial 'deity719/dotfiles not in allowlist'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}
