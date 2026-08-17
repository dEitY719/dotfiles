#!/usr/bin/env bats
# tests/bats/skills/gh_pr_approve_board_sync.bats
# Verify the Step 4.5 `In review` -> `Approved` promotion documented in
#   claude/skills/gh-pr-approve/SKILL.md                        (Step 4.5)
#   claude/skills/gh-pr-approve/references/board-approved-sync.sh.md
# Source-of-truth fixture: _fixtures/gh_pr_approve_board_sync.sh.
#
# Issue #1350: ownership of the `Approved` column moved here from
# gh:pr-reply Step 8 (deleted). Cases:
#   1. approve path (no bypass)          → helper called, bypass unset
#   2. --self-record path (bypass=1)     → helper called with bypass=1 + audit line
#   3. bypass does not leak to caller    → prefix form scoping contract
#   4. helper rc=2                       → soft-fail WARN, rc=0
#   5. --only-from "In review" guard on every call
#   6. doc-guard: gh:pr-reply carries no Step 8 auto-approve any more
#   7. doc-guard: gh:pr-approve documents the Step 4.5 promotion
#   8. doc-guard: no OTHER skill promotes to Approved (the invariant)

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_HELPER_LOG="$(mktemp)"
    export FAKE_HELPER_LOG
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_approve_board_sync.sh"
}

teardown() {
    teardown_isolated_home
    [ -n "$FAKE_HELPER_LOG" ] && rm -f "$FAKE_HELPER_LOG"
    unset FAKE_HELPER_LOG FAKE_HELPER_RC _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
}

@test "board-approve: approve path calls helper WITHOUT the #393 bypass" {
    run gh_pr_approve_board_sync_step45 1349 0
    assert_success
    refute_output --partial 'bypassing #393'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=unset'
    assert_output --partial 'args=pr 1349 Approved --only-from In review'
}

@test "board-approve: --self-record path calls helper WITH bypass=1 + audit line" {
    run gh_pr_approve_board_sync_step45 1349 1
    assert_success
    assert_output --partial 'self-record: bypassing #393 fail-closed guard for PR #1349'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called bypass=1'
    assert_output --partial 'args=pr 1349 Approved --only-from In review'
}

@test "board-approve: bypass env var does NOT leak to caller scope" {
    # The prefix form `_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 helper`
    # must scope the binding to that single call. `env VAR=val funcname`
    # cannot be used — the helper is a shell function, not a binary.
    unset _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS
    gh_pr_approve_board_sync_step45 1349 1 >/dev/null 2>&1
    [ -z "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-}" ]
}

@test "board-approve: helper rc=2 → soft-fail warn, rc=0" {
    FAKE_HELPER_RC=2
    run gh_pr_approve_board_sync_step45 1349 1
    assert_success
    assert_output --partial 'board sync rc=2 — continuing (soft-fail)'
}

@test "board-approve: --only-from \"In review\" guard is present on both paths" {
    # Without it, a re-review on an already-merged PR would drag the
    # `Done` card backwards into `Approved`.
    gh_pr_approve_board_sync_step45 1349 0 >/dev/null 2>&1
    gh_pr_approve_board_sync_step45 1349 1 >/dev/null 2>&1
    run cat "$FAKE_HELPER_LOG"
    assert_success
    [ "$(grep -c -- '--only-from In review' "$FAKE_HELPER_LOG")" = "2" ]
}

@test "issue #1350 doc-guard: gh:pr-reply no longer auto-promotes to Approved" {
    local reply_dir="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-reply"
    [ ! -e "${reply_dir}/references/auto-approve.md" ]
    ! grep -rq 'STEP8_OUTCOME' "$reply_dir"
    ! grep -rq 'GH_PR_REPLY_AUTO_APPROVE_REPOS' "$reply_dir"
}

@test "issue #1350 doc-guard: gh:pr-approve is the only skill promoting to Approved" {
    # The invariant, not just the #1349 regression: no skill other than
    # gh:pr-approve may carry an `_gh_project_status_sync pr … "Approved"`
    # call. Catches Step 8 reappearing anywhere, not only in gh:pr-reply.
    # (`.*` — not `[^\n]*`, which in ERE means "not backslash, not n".)
    run grep -rlE '_gh_project_status_sync[[:space:]]+pr.*"Approved"' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills"
    assert_success
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        case "$hit" in
        */claude/skills/gh-pr-approve/*) ;;
        *) fail "Approved promotion found outside gh:pr-approve: $hit" ;;
        esac
    done <<<"$output"
}

@test "issue #1350 doc-guard: gh:pr-approve documents the Step 4.5 promotion" {
    local approve_dir="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-approve"
    [ -r "${approve_dir}/references/board-approved-sync.sh.md" ]
    grep -q 'board-approved-sync.sh.md' "${approve_dir}/SKILL.md"
    grep -q '_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1' \
        "${approve_dir}/references/board-approved-sync.sh.md"
    grep -q -- '--only-from "In review"' \
        "${approve_dir}/references/board-approved-sync.sh.md"
}
