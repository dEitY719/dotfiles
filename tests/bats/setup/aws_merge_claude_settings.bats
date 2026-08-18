#!/usr/bin/env bats
# tests/bats/setup/aws_merge_claude_settings.bats
# Regression guard for aws/setup.sh's DEPRECATED settings.json handling.
#
# History: this file used to pin the `base * overlay * existing` deep-merge
# that seeded an internal PC's ~/.claude/settings.json (#687), including the
# SSOT-wins fix (#1088) and the key-order churn fix (#1130).
#
# 2026-08-18: that merge is GONE. The org's LLM Gateway migration made
# `gateway-cli setup` the owner of the internal-PC live ~/.claude/settings.json
# (apiKeyHelper / awsCredentialExport / awsAuthRefresh / cleanupPeriodDays /
# env.*), and it also overwrote `.statusLine`. Two writers ping-ponging over one
# file is unfixable, so dotfiles withdrew: `_merge_claude_settings_json` and
# `_archive_legacy_settings_local` were deleted outright and aws/setup.sh keeps
# only the AWS-CLI-side seeding (aws.local.sh + ~/.aws/config). SSOT
# `.hooks`/`.statusLine` now reach the live file via the self-healing
# SessionStart hook (claude/hooks/session-start-settings-drift.sh) — covered by
# tests/bats/skills/session_start_settings_drift_hook.bats.
#
# So the assertions inverted: this file proves the script does NOT re-merge
# settings.json, prints the deprecation notice, and still does its remaining
# job. The whole script is run end-to-end against an isolated dotfiles tree +
# isolated $HOME (it can no longer be sourced piecemeal — there is no merge
# function left to extract).
#
# 2026-08-18 (#1364), ONE narrow exception was carved back out of that
# withdrawal. Claude Code only invokes a SessionStart hook that is registered in
# the LIVE file's own `.hooks.SessionStart`. So if anything wipes live `.hooks`,
# the drift-heal hook's own registration goes with it and the hook can never run
# again to heal itself — a bootstrap single point of failure with no recovery
# path left after the #687 reseed was deleted. `aws/setup.sh` therefore now runs
# `_reregister_session_start_drift_hook` (F-7b): it re-inserts EXACTLY the one
# `.hooks.SessionStart` entry whose command is the drift-heal hook, and nothing
# else. It never creates the live file, never follows a symlinked live file, and
# never reads or writes any other key (notably not the gateway-cli-owned
# apiKeyHelper / awsCredentialExport / awsAuthRefresh / cleanupPeriodDays /
# env.*).
#
# Test layout follows from that split:
#   - setup()'s shared fixture SSOT deliberately does NOT define the drift-heal
#     hook, so F-7b short-circuits and the original "does not touch the live
#     file" cases below still pin the no-op path verbatim.
#   - The "#1364" cases further down install their own SSOT/live fixtures to
#     exercise the registration path (already-registered / missing entry /
#     `.hooks` absent entirely).

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    # Isolated dotfiles tree: aws/setup.sh must be a COPY (it resolves
    # DOTFILES_DIR from its own path, so a symlink would escape isolation and
    # seed aws.local.sh into the real, version-controlled checkout).
    ISO="$TEST_TEMP_HOME/iso"
    mkdir -p "$ISO/aws" "$ISO/claude"
    ln -s "${_BATS_REAL_DOTFILES_ROOT}/shell-common" "$ISO/shell-common"
    cp "${_BATS_REAL_DOTFILES_ROOT}/aws/setup.sh" "$ISO/aws/setup.sh"
    cp "${_BATS_REAL_DOTFILES_ROOT}/aws/aws.local.example" "$ISO/aws/aws.local.example"
    cp "${_BATS_REAL_DOTFILES_ROOT}/aws/aws-config.example" "$ISO/aws/aws-config.example"
    # NOTE: claude/settings.bedrock-overlay.example is deliberately NOT staged —
    # the deprecated script must run clean without the retired overlay template
    # present (the old merge would have hard-failed on a missing overlay).
    SCRIPT="$ISO/aws/setup.sh"

    # dotfiles SSOT stand-in — deliberately carries the fields the old merge
    # would have pushed into the live file.
    cat >"$ISO/claude/settings.json" <<'JSON'
{
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" },
    { "type": "command", "command": "b.sh" }
  ] } ] },
  "statusLine": { "type": "command", "command": "dotfiles-statusline.sh" }
}
JSON

    # Live config as gateway-cli leaves it: its own auth keys, its own
    # statusLine, and a stale single-hook block.
    LIVE_DIR="$HOME/.claude"
    mkdir -p "$LIVE_DIR"
    LIVE="$LIVE_DIR/settings.json"
    # Pin the live-config resolution explicitly. aws/setup.sh's #1364 hook
    # re-registration resolves ${CLAUDE_CONFIG_DIR:-$HOME/.claude}; without this
    # an inherited CLAUDE_CONFIG_DIR would send its WRITE at the developer's real
    # account dir. setup_isolated_home also unsets the inherited value.
    export CLAUDE_CONFIG_DIR="$LIVE_DIR"
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "awsCredentialExport": "gateway-cli creds",
  "awsAuthRefresh": "gateway-cli refresh",
  "cleanupPeriodDays": 365000,
  "env": { "ANTHROPIC_BASE_URL": "https://gateway.internal" },
  "model": "gateway-opus",
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" }
  ] } ] },
  "statusLine": { "type": "command", "command": "gateway-cli statusline" }
}
JSON
    cp "$LIVE" "$TEST_TEMP_HOME/live-before.json"

    printf 'internal' >"$HOME/.dotfiles-setup-mode"
}

teardown() {
    teardown_isolated_home
}

@test "aws/setup.sh deprecated: internal run leaves live settings.json byte-identical" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$LIVE"
    assert_success

    # Specifically: the stale hooks were NOT re-seeded and gateway-cli's
    # statusLine was NOT reverted by this script (that is the drift hook's job).
    run jq -r '[.hooks.SessionStart[0].hooks[].command] | join(",")' "$LIVE"
    [ "$output" = "a.sh" ]
    run jq -r '.statusLine.command' "$LIVE"
    [ "$output" = "gateway-cli statusline" ]
}

@test "aws/setup.sh deprecated: prints the deprecation notice + gateway-cli pointer" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPRECATED"* ]]
    [[ "$output" == *"gateway-cli"* ]]
    [[ "$output" == *"session-start-settings-drift.sh"* ]]
}

@test "aws/setup.sh deprecated: writes no backup / merge artifacts at all" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    run bash -c 'ls "$1"/.claude/settings.json.bedrock-merge-backup.* 2>/dev/null | wc -l' _ "$HOME"
    [ "$output" -eq 0 ]
    run bash -c 'ls "$1"/.claude/settings.json.* 2>/dev/null | wc -l' _ "$HOME"
    [ "$output" -eq 0 ]
}

@test "aws/setup.sh deprecated: settings.local.json is no longer archived away" {
    # #924 made settings.local.json the sanctioned personal-override slot, so
    # the old #687 auto-archive became actively harmful and was removed.
    printf '{ "model": "sonnet" }' >"$LIVE_DIR/settings.local.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ -f "$LIVE_DIR/settings.local.json" ]
    run jq -r '.model' "$LIVE_DIR/settings.local.json"
    [ "$output" = "sonnet" ]
    run bash -c 'ls "$1"/.claude/settings.local.json.deprecated-687.* 2>/dev/null | wc -l' _ "$HOME"
    [ "$output" -eq 0 ]
}

@test "aws/setup.sh deprecated: still seeds aws.local.sh + ~/.aws/config" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ -f "$ISO/aws/aws.local.sh" ]
    [ -f "$HOME/.aws/config" ]
}

@test "aws/setup.sh deprecated: no settings.json merge code remains in the script" {
    # Guard against someone re-wiring a second writer to the live file. The
    # header comment still NAMES the removed helpers (explaining why they are
    # gone), so match only definitions/calls — a line that STARTS with the name.
    run grep -nE '^[[:space:]]*(_merge_claude_settings_json|_archive_legacy_settings_local)' "$SCRIPT"
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# #1364 — F-7b: the drift-heal hook's OWN .hooks.SessionStart registration.
# ---------------------------------------------------------------------------

# Deliberately NOT the ${HOME}/dotfiles/... literal the real SSOT ships: F-7b
# must read the command string out of the SSOT rather than hardcode it, so a
# non-standard checkout path still produces the right entry.
DRIFT_HOOK_CMD='/opt/checkout/dotfiles/claude/hooks/session-start-settings-drift.sh'
REG_BACKUP_SUFFIX='.pre-sessionstart-hook-reg.backup'

# Overwrite the shared fixture's SSOT with one that DOES define the drift-heal
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
    _ssot_with_drift_hook
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
    _ssot_with_drift_hook
    # The SPOF as it actually shows up: .hooks.SessionStart survives but the
    # drift-heal entry is gone (here: another tool rewrote the array).
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "awsCredentialExport": "gateway-cli creds",
  "awsAuthRefresh": "gateway-cli refresh",
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
    _ssot_with_drift_hook
    # The literal bootstrap deadlock from the issue body: jq 'del(.hooks)'.
    cat >"$LIVE" <<'JSON'
{
  "apiKeyHelper": "gateway-cli token",
  "awsCredentialExport": "gateway-cli creds",
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
    _ssot_with_drift_hook
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
    _ssot_with_drift_hook
    rm -f "$LIVE"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ ! -e "$LIVE" ]
    [ ! -e "${LIVE}${REG_BACKUP_SUFFIX}" ]
}

@test "#1364: a symlinked live settings.json is never rewritten" {
    _ssot_with_drift_hook
    rm -f "$LIVE"
    cat >"$TEST_TEMP_HOME/symlink-target.json" <<'JSON'
{ "apiKeyHelper": "gateway-cli token" }
JSON
    ln -s "$TEST_TEMP_HOME/symlink-target.json" "$LIVE"
    cp "$TEST_TEMP_HOME/symlink-target.json" "$TEST_TEMP_HOME/live-before.json"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    [ -L "$LIVE" ]
    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$TEST_TEMP_HOME/symlink-target.json"
    assert_success
    [ ! -e "${LIVE}${REG_BACKUP_SUFFIX}" ]
}

@test "aws/setup.sh deprecated: non-internal mode is still a plain no-op" {
    printf 'external' >"$HOME/.dotfiles-setup-mode"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip (internal-only)"* ]]
    [[ "$output" != *"DEPRECATED"* ]]

    run cmp -s "$TEST_TEMP_HOME/live-before.json" "$LIVE"
    assert_success
    [ ! -f "$ISO/aws/aws.local.sh" ]
}
