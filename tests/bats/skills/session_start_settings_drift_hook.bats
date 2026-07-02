#!/usr/bin/env bats
# tests/bats/skills/session_start_settings_drift_hook.bats
# Verify the SessionStart hook documented in
#   claude/hooks/session-start-settings-drift.sh (issue #1086)
#
# The hook compares the `.hooks` block of the dotfiles SSOT
# (claude/settings.json, resolved relative to the hook's own dir) against the
# live ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json and warns on drift.
#
# Cases:
#   1. non-SessionStart event   → exit 0, silent
#   2. empty stdin              → exit 0, silent
#   3. .hooks identical         → exit 0, silent (no drift)
#   4. live missing a hook      → exit 0, drift warning (stderr + additionalContext)
#   5. live file absent         → exit 0, silent
#   6. internal mode            → drift message points at ./aws/setup.sh

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    # Isolated dotfiles/claude tree so SSOT (…/claude/settings.json, resolved
    # relative to the hook) is fully under test control.
    ISO_CLAUDE="$TEST_TEMP_HOME/iso/claude"
    mkdir -p "$ISO_CLAUDE/hooks"
    cp "${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/session-start-settings-drift.sh" \
        "$ISO_CLAUDE/hooks/session-start-settings-drift.sh"
    HOOK="$ISO_CLAUDE/hooks/session-start-settings-drift.sh"

    # SSOT with a two-hook SessionStart block.
    SSOT="$ISO_CLAUDE/settings.json"
    cat >"$SSOT" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" },
  { "type": "command", "command": "b.sh" }
] } ] } }
JSON

    # Live config dir (CLAUDE_CONFIG_DIR override).
    LIVE_DIR="$TEST_TEMP_HOME/live"
    mkdir -p "$LIVE_DIR"
    export CLAUDE_CONFIG_DIR="$LIVE_DIR"
}

teardown() {
    teardown_isolated_home
}

# Feed a SessionStart payload (or the given event) to the hook on stdin.
# stderr is redirected to a file so $output holds only the stdout JSON
# (bats otherwise merges the two, corrupting the JSON parse).
_run_hook() {
    local event="${1:-SessionStart}"
    run bash -c "printf '{\"hook_event_name\":\"%s\"}' '$event' | '$HOOK' 2>'$TEST_TEMP_HOME/stderr'"
    STDERR_CONTENT=$(cat "$TEST_TEMP_HOME/stderr" 2>/dev/null)
}

@test "settings-drift: non-SessionStart event → silent, exit 0" {
    cp "$SSOT" "$LIVE_DIR/settings.json"
    _run_hook "Stop"
    assert_success
    [ -z "$output" ]
}

@test "settings-drift: empty stdin → silent, exit 0" {
    cp "$SSOT" "$LIVE_DIR/settings.json"
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ -z "$output" ]
}

@test "settings-drift: identical .hooks → no drift, silent exit 0" {
    cp "$SSOT" "$LIVE_DIR/settings.json"
    _run_hook
    assert_success
    [ -z "$output" ]
}

@test "settings-drift: live missing a hook → drift warning" {
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" }
] } ] } }
JSON
    _run_hook
    assert_success
    assert_output --partial '"hookEventName": "SessionStart"'
    assert_output --partial 'hook drift'
    [[ "$STDERR_CONTENT" == *"hook drift"* ]]

    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"./setup.sh"* ]]
}

@test "settings-drift: overlay-style extra top-level key is ignored (only .hooks compared)" {
    # Live has identical .hooks but an extra Bedrock-overlay-style key —
    # must NOT be flagged as drift.
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "model": "global.anthropic.claude-opus-4-7",
  "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" },
  { "type": "command", "command": "b.sh" }
] } ] } }
JSON
    _run_hook
    assert_success
    [ -z "$output" ]
}

@test "settings-drift: live settings.json absent → silent, exit 0" {
    _run_hook
    assert_success
    [ -z "$output" ]
}

@test "settings-drift: internal mode → message points at ./aws/setup.sh" {
    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" }
] } ] } }
JSON
    _run_hook
    assert_success
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"./aws/setup.sh"* ]]
}
