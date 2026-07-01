#!/usr/bin/env bats
# tests/bats/skills/session_start_pc_context_hook.bats
# Verify the SessionStart hook documented in
#   claude/hooks/session-start-pc-context.sh (issue #1052)
#
# Cases:
#   1. mode file missing              → exit 0, no output (never blocks session)
#   2. unrecognized mode value        → exit 0, no output
#   3. internal (text)                → JSON additionalContext with host
#   4. legacy numeric "3" (external)  → canonicalized to "external"
#   5. jq unavailable                 → plain-text fallback on stdout

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/session-start-pc-context.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "session-start-pc-context: mode file missing → silent, exit 0" {
    run "$HOOK"
    assert_success
    [ -z "$output" ]
}

@test "session-start-pc-context: unrecognized mode value → silent, exit 0" {
    printf 'bogus' >"$HOME/.dotfiles-setup-mode"
    run "$HOOK"
    assert_success
    [ -z "$output" ]
}

@test "session-start-pc-context: internal mode → JSON additionalContext" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    run "$HOOK"
    assert_success
    assert_output --partial '"hookEventName": "SessionStart"'
    assert_output --partial 'Dotfiles PC setup-mode: internal'

    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"host: "* ]]
}

@test "session-start-pc-context: legacy numeric 3 canonicalizes to external" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
    printf '3' >"$HOME/.dotfiles-setup-mode"
    run "$HOOK"
    assert_success
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == "Dotfiles PC setup-mode: external"* ]]
}

@test "session-start-pc-context: no jq → plain-text fallback" {
    printf 'public' >"$HOME/.dotfiles-setup-mode"
    fake_bin="$TEST_TEMP_HOME/fakebin"
    mkdir -p "$fake_bin"
    for c in bash hostname tr cat printf; do
        real="$(command -v "$c")"
        [ -n "$real" ] && ln -sf "$real" "$fake_bin/$c"
    done
    run env -i HOME="$HOME" PATH="$fake_bin" "$HOOK"
    assert_success
    assert_output --partial "Dotfiles PC setup-mode: public"
    [[ "$output" != *"hookSpecificOutput"* ]]
}
