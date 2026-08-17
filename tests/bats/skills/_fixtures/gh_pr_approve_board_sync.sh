#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_approve_board_sync.sh
# Source-of-truth mirror for the Step 4.5 board-promotion snippet
# documented in claude/skills/gh-pr-approve/references/board-approved-sync.sh.md.
#
# Issue #1350 moved `Approved` column ownership out of gh:pr-reply
# (its allowlist-gated Step 8 auto-approve, removed) and into
# gh:pr-approve, where a human explicitly invokes the skill. This
# fixture keeps the two load-bearing details under test:
#
#   1. the POSIX prefix form `VAR=val funcname …` for the #393
#      fail-closed bypass (a shell function cannot be invoked via
#      `env VAR=val funcname`), scoped to one call only; and
#   2. the `--only-from "In review"` guard that stops a `Done` card
#      from being dragged back into `Approved`.
#
# Keep this file in sync with board-approved-sync.sh.md. If the block
# changes, mirror the change here so the bats suite catches drift.

# Stand-in for _gh_project_status_sync. The real helper lives in
# shell-common/functions/gh_project_status.sh; tests inject behaviour
# via FAKE_HELPER_RC and FAKE_HELPER_LOG. Records the bypass binding it
# observed plus its full argv.
_gh_project_status_sync() {
    : "${FAKE_HELPER_LOG:?FAKE_HELPER_LOG must be set by the test}"
    printf 'helper called bypass=%s args=%s\n' \
        "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-unset}" "$*" >>"$FAKE_HELPER_LOG"
    return "${FAKE_HELPER_RC-0}"
}

# Mirrors the Step 4.5 block. Args:
#   $1 PR number
#   $2 BOARD_BYPASS — "1" only on the self-PR `--self-record` path
# Always returns 0 (soft-fail policy: board bookkeeping never blocks
# the Step 5 report).
gh_pr_approve_board_sync_step45() {
    local PR_NUMBER="$1" BOARD_BYPASS="${2-0}" _rc=0

    if [ "${BOARD_BYPASS:-0}" = "1" ]; then
        printf '[gh-pr-approve] self-record: bypassing #393 fail-closed guard for PR #%s (operator intent).\n' \
            "$PR_NUMBER" >&2
        _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
            _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review" || _rc=$?
    else
        _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review" || _rc=$?
    fi

    if [ "$_rc" -ne 0 ]; then
        printf '[gh-pr-approve] board sync rc=%s — continuing (soft-fail).\n' "$_rc" >&2
    fi

    return 0
}
