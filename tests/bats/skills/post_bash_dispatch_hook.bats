#!/usr/bin/env bats
# tests/bats/skills/post_bash_dispatch_hook.bats
# Verify the PostToolUse:Bash dispatcher documented in
#   claude/hooks/post-bash-dispatch.sh
# routes each event to the correct handler (or to none), forwarding the
# untouched stdin JSON. Issue #1144.
#
# POST_BASH_DISPATCH_DIR points the dispatcher at stub handlers that record
# which one was entered plus the exact stdin they received — so the real
# board-sync / manifest-sync logic never runs and cannot mask a routing bug.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/post-bash-dispatch.sh"

setup() {
    setup_isolated_home
    STUB_DIR="$TEST_TEMP_HOME/hooks"
    mkdir -p "$STUB_DIR"
    ROUTE_LOG="$TEST_TEMP_HOME/route.log"
    : > "$ROUTE_LOG"
    cat > "$STUB_DIR/post-gh-pr-create.sh" <<EOF
#!/usr/bin/env bash
printf 'pr-create:%s\n' "\$(cat)" >> "$ROUTE_LOG"
EOF
    cat > "$STUB_DIR/plugin-sync.sh" <<EOF
#!/usr/bin/env bash
printf 'plugin-sync:%s\n' "\$(cat)" >> "$ROUTE_LOG"
EOF
    chmod +x "$STUB_DIR/post-gh-pr-create.sh" "$STUB_DIR/plugin-sync.sh"
    export POST_BASH_DISPATCH_DIR="$STUB_DIR"
}

teardown() {
    teardown_isolated_home
    unset POST_BASH_DISPATCH_DIR
}

@test "dispatch: non-matching Bash command → no handler spawned, exit 0" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}

@test "dispatch: gh pr create → only post-gh-pr-create entered" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title foo"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^pr-create:' "$ROUTE_LOG"
    ! grep -q '^plugin-sync:' "$ROUTE_LOG"
}

@test "dispatch: env-prefixed gh pr create still routes (#390 word-boundary)" {
    payload='{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x gh pr create --draft"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^pr-create:' "$ROUTE_LOG"
}

@test "dispatch: claude plugin install → only plugin-sync entered" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install foo@bar"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^plugin-sync:' "$ROUTE_LOG"
    ! grep -q '^pr-create:' "$ROUTE_LOG"
}

@test "dispatch: non-Bash tool → immediate exit, no handler" {
    payload='{"tool_name":"Read","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}

@test "dispatch: empty stdin → exit 0, no handler" {
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}

@test "dispatch: stdin forwarded verbatim to the routed handler" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/o/r/pull/1"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -qF "pr-create:$payload" "$ROUTE_LOG"
}

@test "dispatch: non-executable handler → silent no-op, exit 0 (PR #1145 gemini)" {
    # Defensive: a missing/non-executable handler must be a silent no-op, not
    # stderr noise + a non-zero pipeline. Strip +x so the -x guard skips it.
    chmod -x "$STUB_DIR/post-gh-pr-create.sh"
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}
