#!/usr/bin/env bats
# tests/bats/skills/session_start_settings_drift_hook.bats
# Verify the SessionStart hook documented in
#   claude/hooks/session-start-settings-drift.sh (issue #1086)
#
# The hook compares the `.hooks` + `.statusLine` blocks of the dotfiles SSOT
# (claude/settings.json, resolved relative to the hook's own dir) against the
# live ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json. Non-internal modes
# get an advisory; internal mode auto-heals those two keys in place
# (2026-08-18 — gateway-cli owns the rest of the live file, and aws/setup.sh's
# old re-seed merge is deprecated, so nothing else carries SSOT changes over).
#
# Cases:
#   1. non-SessionStart event   → exit 0, silent
#   2. empty stdin              → exit 0, silent
#   3. .hooks identical         → exit 0, silent (no drift)
#   4. live missing a hook      → exit 0, drift warning (stderr + additionalContext)
#   5. live file absent         → exit 0, silent
#   6. internal + .hooks drift  → live patched from SSOT, backup, "auto-corrected"
#   7. internal + .statusLine drift → same, gateway-owned keys untouched
#   8. internal + .statusLine drift but SSOT has none → only .hooks healed,
#      message doesn't overclaim .statusLine was corrected
#   9. non-internal + drift     → advisory only, live file NOT mutated

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

# --- Internal-mode self-heal (2026-08-18) ---------------------------------
# aws/setup.sh no longer re-seeds settings.json (gateway-cli owns the file), so
# on internal PCs the hook patches the two dotfiles-owned keys itself.

@test "settings-drift: internal mode + .hooks drift → live patched from SSOT + backup" {
    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" }
] } ] } }
JSON
    _run_hook
    assert_success

    # Advisory still emitted, but reworded as already-fixed.
    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"auto-corrected"* ]]
    [[ "$ctx" == *".hooks"* ]]
    [[ "$ctx" != *"./setup.sh"* ]]

    # Live .hooks now matches the SSOT exactly.
    run bash -c "jq -S -c '.hooks' '$LIVE_DIR/settings.json'"
    ssot_hooks=$(jq -S -c '.hooks' "$SSOT")
    [ "$output" = "$ssot_hooks" ]

    # Latest-only backup lives outside the dotfiles tree (#554/#919).
    [ -f "$HOME/.claude-backups/settings.json.pre-drift-heal.backup" ]
    run jq -r '[.hooks.SessionStart[0].hooks[].command] | join(",")' \
        "$HOME/.claude-backups/settings.json.pre-drift-heal.backup"
    [ "$output" = "a.sh" ]
}

@test "settings-drift: internal mode + .statusLine drift → patched, gateway keys untouched" {
    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    # SSOT gains a statusLine; .hooks stay identical so ONLY statusLine drifts.
    cat >"$SSOT" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" },
  { "type": "command", "command": "b.sh" }
] } ] },
  "statusLine": { "type": "command", "command": "dotfiles-statusline.sh" } }
JSON
    # Live: gateway-cli-owned keys + a clobbered statusLine.
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "apiKeyHelper": "gateway-cli token",
  "awsCredentialExport": "gateway-cli creds",
  "awsAuthRefresh": "gateway-cli refresh",
  "cleanupPeriodDays": 365000,
  "env": { "ANTHROPIC_BASE_URL": "https://gateway.internal" },
  "model": "gateway-opus",
  "availableModels": ["gateway-opus"],
  "enabledPlugins": { "gateway-migration": true },
  "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" },
  { "type": "command", "command": "b.sh" }
] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" } }
JSON
    _run_hook
    assert_success

    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"auto-corrected"* ]]
    [[ "$ctx" == *".statusLine"* ]]

    # statusLine restored from the SSOT.
    run jq -r '.statusLine.command' "$LIVE_DIR/settings.json"
    [ "$output" = "dotfiles-statusline.sh" ]

    # Every gateway-cli / Claude-Code-native key survives byte-for-byte.
    run jq -r '.apiKeyHelper' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-cli token" ]
    run jq -r '.awsCredentialExport' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-cli creds" ]
    run jq -r '.awsAuthRefresh' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-cli refresh" ]
    run jq -r '.cleanupPeriodDays' "$LIVE_DIR/settings.json"
    [ "$output" = "365000" ]
    run jq -r '.env.ANTHROPIC_BASE_URL' "$LIVE_DIR/settings.json"
    [ "$output" = "https://gateway.internal" ]
    run jq -r '.model' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-opus" ]
    run jq -r '.availableModels | join(",")' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-opus" ]
    run jq -r '.enabledPlugins."gateway-migration"' "$LIVE_DIR/settings.json"
    [ "$output" = "true" ]

    [ -f "$HOME/.claude-backups/settings.json.pre-drift-heal.backup" ]
}

@test "settings-drift: internal mode + .statusLine drift but SSOT defines none → only .hooks healed, message doesn't overclaim" {
    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    # SSOT has NO .statusLine at all — the heal has nothing to put back.
    cat >"$SSOT" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" },
  { "type": "command", "command": "b.sh" }
] } ] } }
JSON
    # Live: .hooks drifted (missing b.sh) AND carries a statusLine the SSOT
    # doesn't define — both differ from SSOT, but only .hooks is healable.
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" }
] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" } }
JSON
    _run_hook
    assert_success

    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"auto-corrected"* ]]
    # Message must credit only what was actually healed...
    [[ "$ctx" == *".hooks"* ]]
    # ...and must NOT claim .statusLine was corrected when it was skipped.
    [[ "$ctx" != *"in: .hooks, .statusLine"* ]]
    [[ "$ctx" == *"NOT auto-corrected"* ]]

    # .hooks healed from SSOT.
    run bash -c "jq -S -c '.hooks' '$LIVE_DIR/settings.json'"
    ssot_hooks=$(jq -S -c '.hooks' "$SSOT")
    [ "$output" = "$ssot_hooks" ]

    # .statusLine left exactly as-is — nothing to heal it with.
    run jq -r '.statusLine.command' "$LIVE_DIR/settings.json"
    [ "$output" = "gateway-cli statusline" ]
}

@test "settings-drift: non-internal mode + drift → advisory only, live NOT mutated" {
    printf 'external' >"$HOME/.dotfiles-setup-mode"
    cat >"$LIVE_DIR/settings.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "a.sh" }
] } ] } }
JSON
    cp "$LIVE_DIR/settings.json" "$TEST_TEMP_HOME/live-before.json"

    _run_hook
    assert_success

    ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$ctx" == *"./setup.sh"* ]]
    [[ "$ctx" != *"auto-corrected"* ]]

    # Byte-identical: the advisory path never writes.
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$LIVE_DIR/settings.json"
    assert_success
    [ ! -e "$HOME/.claude-backups/settings.json.pre-drift-heal.backup" ]
}
