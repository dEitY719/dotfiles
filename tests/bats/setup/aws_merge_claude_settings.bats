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
# So the assertions inverted: this file now proves the script does NOT touch
# settings.json, prints the deprecation notice, and still does its remaining
# job. The whole script is run end-to-end against an isolated dotfiles tree +
# isolated $HOME (it can no longer be sourced piecemeal — there is no merge
# function left to extract).

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
