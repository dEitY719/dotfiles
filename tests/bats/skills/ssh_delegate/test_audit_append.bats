#!/usr/bin/env bats
# tests/bats/skills/ssh_delegate/test_audit_append.bats
# The audit log is append-only JSONL: every event adds exactly one valid JSON
# line, special characters are escaped, and the path honors the env override.

load '../../test_helper'

SKILL_LIB="${DOTFILES_ROOT}/claude/skills/devx-ssh-delegate/lib"

setup() {
    setup_isolated_home
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/audit.sh"
    export DEVX_SSH_AUDIT_LOG="${TEST_TEMP_HOME}/state/ssh-delegations.log"
}

teardown() { teardown_isolated_home; }

@test "audit_log_path honors DEVX_SSH_AUDIT_LOG" {
    run audit_log_path
    assert_output "$DEVX_SSH_AUDIT_LOG"
}

@test "each event appends exactly one line and auto-creates the dir" {
    audit_log_event add gpu1-bwyoon 'bwyoon@host'
    audit_log_event verify-ok gpu1-bwyoon ''
    assert [ -f "$DEVX_SSH_AUDIT_LOG" ]
    run wc -l <"$DEVX_SSH_AUDIT_LOG"
    assert_output '2'
}

@test "appended lines are valid JSON with the expected fields" {
    audit_log_event add gpu1-bwyoon 'bwyoon@12.81.221.129'
    run jq -r '.event' "$DEVX_SSH_AUDIT_LOG"
    assert_output 'add'
    run jq -r '.alias' "$DEVX_SSH_AUDIT_LOG"
    assert_output 'gpu1-bwyoon'
    run jq -r '.detail' "$DEVX_SSH_AUDIT_LOG"
    assert_output 'bwyoon@12.81.221.129'
    run jq -r 'has("ts") and has("actor")' "$DEVX_SSH_AUDIT_LOG"
    assert_output 'true'
}

@test "special characters in detail are JSON-escaped (stays parseable)" {
    audit_log_event note gpu1 'has "quotes" and a \backslash'
    run jq -r '.detail' "$DEVX_SSH_AUDIT_LOG"
    assert_success
    assert_output 'has "quotes" and a \backslash'
}

@test "log is append-only — earlier lines survive later events" {
    audit_log_event add a ''
    audit_log_event revoke a ''
    run jq -r '.event' "$DEVX_SSH_AUDIT_LOG"
    assert_line --index 0 'add'
    assert_line --index 1 'revoke'
}
