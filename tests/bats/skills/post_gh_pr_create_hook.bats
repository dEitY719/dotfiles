#!/usr/bin/env bats
# tests/bats/skills/post_gh_pr_create_hook.bats
# Verify the PostToolUse hook documented in
#   claude/hooks/post-gh-pr-create.sh
# Source-of-truth fixture: _fixtures/post_gh_pr_create_hook.sh
# (provides a fake gh_project_status.sh that records every call).
#
# Five cases drawn from issue #390's compatibility matrix:
#   1. tool_name != Bash               → exit 0, no sync
#   2. Bash + non-`gh pr create` cmd   → exit 0, no sync
#   3. Bash + `gh pr create` + URL     → 1 call: pr <num> "In review"
#   4. Bash + `gh pr create` + no URL  → exit 0, no sync (graceful)
#   5. Empty stdin                     → exit 0, no sync (graceful)

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/post-gh-pr-create.sh"

setup() {
    setup_isolated_home
    # Stage a fake shell-common with a stub gh_project_status.sh that
    # records every call into $CALL_LOG. The hook sources via
    # $SHELL_COMMON/functions/gh_project_status.sh, so wiring SHELL_COMMON
    # to a tmp tree lets us observe sync calls without a live projectV2.
    FAKE_SHELL_COMMON="$TEST_TEMP_HOME/shell-common"
    mkdir -p "$FAKE_SHELL_COMMON/functions"
    CALL_LOG="$TEST_TEMP_HOME/calls.log"
    : > "$CALL_LOG"
    cat > "$FAKE_SHELL_COMMON/functions/gh_project_status.sh" <<EOF
_gh_project_status_sync() { printf 'sync %s\n' "\$*" >> "$CALL_LOG"; return 0; }
_gh_pr_closing_issue_numbers() { return 0; }  # no linked issues by default
EOF
    export SHELL_COMMON="$FAKE_SHELL_COMMON"
    # Block real gh from running — the hook only calls `gh repo view` for
    # GH_REPO; passing GH_REPO directly avoids the network and the PATH lookup.
    export GH_REPO="owner/repo"
}

teardown() {
    teardown_isolated_home
    unset SHELL_COMMON GH_REPO
}

@test "post-gh-pr-create: tool_name != Bash → no sync" {
    payload='{"tool_name":"Read","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/owner/repo/pull/42"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: Bash + non-pr-create command → no sync" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr list"},"tool_response":{"output":"https://github.com/owner/repo/pull/42"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: Bash + gh pr create + PR URL → sync called" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title foo"},"tool_response":{"output":"https://github.com/owner/repo/pull/123\n"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    # Expect exactly one sync invocation for the PR card itself.
    assert_output --partial 'PR #123 → "In review"'
    grep -q '^sync pr 123 In review$' "$CALL_LOG"
}

@test "post-gh-pr-create: Bash + gh pr create + no URL → no sync" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"error: something went wrong"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: empty stdin → no sync" {
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ ! -s "$CALL_LOG" ]
}

@test "post-gh-pr-create: env-prefixed gh pr create still matches" {
    # Regression for the regex — `FOO=bar gh pr create` and `command gh pr create`
    # should both trigger. Without the (^|space) anchor, prefixes break detection.
    payload='{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x gh pr create --draft"},"tool_response":{"output":"https://github.com/owner/repo/pull/7"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^sync pr 7 In review$' "$CALL_LOG"
}
