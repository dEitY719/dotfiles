#!/usr/bin/env bats
# tests/bats/setup/register_drift_hook.bats
# claude/tools/register-drift-hook.sh — F-7b (#1364), relocated by #2097. It
# re-inserts EXACTLY the drift-heal hook's own
# `.hooks.SessionStart` entry into the gateway-cli-owned live settings.json and
# nothing else. It never creates the live file, never follows a symlinked live
# file, and never reads or writes any other key.

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    # Isolated dotfiles tree: the script must be a COPY (it resolves
    # DOTFILES_DIR from its own path, so a symlink would read the real SSOT).
    ISO="$TEST_TEMP_HOME/iso"
    mkdir -p "$ISO/claude/tools"
    ln -s "${_BATS_REAL_DOTFILES_ROOT}/shell-common" "$ISO/shell-common"
    cp "${_BATS_REAL_DOTFILES_ROOT}/claude/tools/register-drift-hook.sh" "$ISO/claude/tools/"
    SCRIPT="$ISO/claude/tools/register-drift-hook.sh"

    LIVE_DIR="$HOME/.claude"
    mkdir -p "$LIVE_DIR"
    LIVE="$LIVE_DIR/settings.json"
    # Pin the live-config resolution so an inherited CLAUDE_CONFIG_DIR never
    # sends the WRITE at the developer's real account dir.
    export CLAUDE_CONFIG_DIR="$LIVE_DIR"
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "cleanupPeriodDays": 365000,
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" }
  ] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" }
}
JSON
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"

    printf 'internal' >"$HOME/.dotfiles-setup-mode"
    _ssot_with_drift_hook
}

teardown() {
    teardown_isolated_home
}


# ---------------------------------------------------------------------------
# #1364 — F-7b: the drift-heal hook's OWN .hooks.SessionStart registration.
# ---------------------------------------------------------------------------

# Deliberately NOT the ${HOME}/dotfiles/... literal the real SSOT ships: F-7b
# must read the command string out of the SSOT rather than hardcode it, so a
# non-standard checkout path still produces the right entry.
DRIFT_HOOK_CMD='/opt/checkout/dotfiles/claude/hooks/session-start-settings-drift.sh'
REG_BACKUP_SUFFIX='.pre-sessionstart-hook-reg.backup'

# Isolated SSOT (written by setup) that DOES define the drift-heal
# hook (plus an unrelated sibling hook, so we can prove only one entry matches).
_ssot_with_drift_hook() {
    cat >"$ISO/claude/settings.json" <<JSON
{
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "/opt/checkout/dotfiles/claude/hooks/session-start-pc-context.sh" },
    { "type": "command", "command": "${DRIFT_HOOK_CMD}" }
  ] } ] },
  "statusLine": { "type": "command", "command": "dotfiles-statusline.sh" }
}
JSON
}

# Shared by the two F-7b write-path tests: every non-.hooks key still matches
# the pre-run snapshot (value-wise), and a latest-only backup of that snapshot
# was left behind (#806). Expects $TEST_TEMP_HOME/live-before.json pre-run.
_assert_other_keys_preserved_and_backed_up() {
    run bash -c 'diff <(jq -S -c "del(.hooks)" "$1") <(jq -S -c "del(.hooks)" "$2")' \
        _ "$TEST_TEMP_HOME/live-before.json" "$LIVE"
    assert_success

    [ -f "${LIVE}${REG_BACKUP_SUFFIX}" ]
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "${LIVE}${REG_BACKUP_SUFFIX}"
    assert_success
}

@test "#1364: live settings.json already registering the drift hook is left untouched" {
    cat >"$LIVE" <<JSON
{
  "apiKeyHelper": "gateway-cli token",
  "cleanupPeriodDays": 365000,
  "env": { "ANTHROPIC_BASE_URL": "https://gateway.internal" },
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "${DRIFT_HOOK_CMD}" }
  ] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" }
}
JSON
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Byte-identical: the already-registered case must not rewrite the file at
    # all (no jq re-serialisation churn, no key reordering).
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$LIVE"
    assert_success

    [ ! -e "${LIVE}${REG_BACKUP_SUFFIX}" ]
}

@test "#1364: missing drift-hook entry is re-registered, siblings preserved" {
    # The SPOF as it actually shows up: .hooks.SessionStart survives but the
    # drift-heal entry is gone (here: another tool rewrote the array).
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "cleanupPeriodDays": 365000,
  "env": { "ANTHROPIC_BASE_URL": "https://gateway.internal" },
  "model": "gateway-opus",
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "unrelated-other-tool.sh" }
  ] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" }
}
JSON
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-start-settings-drift.sh"* ]]

    # The drift-heal entry is now present exactly once.
    run jq --arg c "$DRIFT_HOOK_CMD" \
        '[.hooks.SessionStart[]?.hooks[]?.command | select(. == $c)] | length' "$LIVE"
    [ "$output" -eq 1 ]

    # The pre-existing unrelated hook entry survived.
    run jq -r '[.hooks.SessionStart[]?.hooks[]?.command | select(. == "unrelated-other-tool.sh")] | length' "$LIVE"
    [ "$output" -eq 1 ]

    _assert_other_keys_preserved_and_backed_up
}

@test "#1364: live settings.json with .hooks entirely absent gets the hook back" {
    # The literal bootstrap deadlock from the issue body: jq 'del(.hooks)'.
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "cleanupPeriodDays": 365000,
  "env": { "ANTHROPIC_BASE_URL": "https://gateway.internal" },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" }
}
JSON
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    run jq -S -c '.hooks' "$LIVE"
    [ "$output" = "{\"SessionStart\":[{\"hooks\":[{\"command\":\"${DRIFT_HOOK_CMD}\",\"type\":\"command\"}]}]}" ]

    _assert_other_keys_preserved_and_backed_up
}

@test "#1364: re-registration is idempotent across two runs" {
    run bash -c 'jq "del(.hooks)" "$1" > "$1.t" && mv "$1.t" "$1"' _ "$LIVE"
    assert_success

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    cp "$LIVE" "$TEST_TEMP_HOME/live-after-first.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    run cmp -s "$TEST_TEMP_HOME/live-after-first.json" "$LIVE"
    assert_success
    run jq --arg c "$DRIFT_HOOK_CMD" \
        '[.hooks.SessionStart[]?.hooks[]?.command | select(. == $c)] | length' "$LIVE"
    [ "$output" -eq 1 ]
}

@test "#1364: never creates the live settings.json when it is absent" {
    rm -f "$LIVE"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ ! -e "$LIVE" ]
    [ ! -e "${LIVE}${REG_BACKUP_SUFFIX}" ]
}

@test "#1364: a symlinked live settings.json is never rewritten" {
    rm -f "$LIVE"
    cat >"$TEST_TEMP_HOME/symlink-target.json" <<'JSON'
{ "apiKeyHelper": "gateway-cli token" }
JSON
    ln -s "$TEST_TEMP_HOME/symlink-target.json" "$LIVE"
    cp "$TEST_TEMP_HOME/symlink-target.json" "$TEST_TEMP_HOME/live-before.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"symlink"* ]]

    [ -L "$LIVE" ]
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$TEST_TEMP_HOME/symlink-target.json"
    assert_success
    [ ! -e "${LIVE}${REG_BACKUP_SUFFIX}" ]
}

@test "register-drift-hook: non-internal mode is a silent no-op" {
    run bash -c 'jq "del(.hooks)" "$1" > "$1.t" && mv "$1.t" "$1"' _ "$LIVE"
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"
    printf 'external' >"$HOME/.dotfiles-setup-mode"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$LIVE"
    assert_success
}
