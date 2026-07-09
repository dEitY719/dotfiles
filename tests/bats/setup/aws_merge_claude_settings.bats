#!/usr/bin/env bats
# tests/bats/setup/aws_merge_claude_settings.bats
# Regression guard for aws/setup.sh → _merge_claude_settings_json() (issue #1088).
#
# Bug (#1088): the deep-merge `base * overlay * existing` let the live real file
# (existing) win on EVERY field. jq's `*` recurses objects but REPLACES arrays
# with the RHS, so a stale `existing.hooks.SessionStart` array permanently
# clobbered the SSOT `base.hooks.SessionStart` — new hooks added to the SSOT
# never propagated to already-set-up PCs.
#
# Fix: SSOT-owned fields (hooks / statusLine from base, availableModels /
# modelOverrides from overlay) are del'd from `existing` before the merge so the
# SSOT values survive. User-owned fields (model, custom keys) stay preserved.
#
# The real function is extracted from aws/setup.sh at test time (the script has
# no source guard and `exit 0`s for non-internal mode, so it can't be sourced
# wholesale) and run against isolated fixtures with ux_* stubbed to no-ops.

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    # Extract just _merge_claude_settings_json() from the real script, source
    # it, and stub the ux_* helpers it calls. This tests the SHIPPED jq program,
    # not a copy — any drift in the merge logic breaks this test.
    local fn_file="$TEST_TEMP_HOME/merge_fn.sh"
    # Spacing-tolerant so a shfmt reformat of the `func() {` line can't
    # silently break extraction (PR #1089 review — gemini).
    awk '/^_merge_claude_settings_json[[:space:]]*\([[:space:]]*\)[[:space:]]*\{/{grab=1} grab{print} /^}/{if(grab)exit}' \
        "${_BATS_REAL_DOTFILES_ROOT}/aws/setup.sh" >"$fn_file"
    # shellcheck disable=SC1090
    ux_success() { :; }
    ux_error() { echo "ux_error: $*" >&2; }
    ux_warning() { :; }
    ux_bullet() { :; }
    . "$fn_file"

    BASE="$TEST_TEMP_HOME/base.json"
    OVERLAY="$TEST_TEMP_HOME/overlay.json"
    TGT="$TEST_TEMP_HOME/settings.json"

    # SSOT base: 3-hook SessionStart block + statusLine.
    cat >"$BASE" <<'JSON'
{
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" },
    { "type": "command", "command": "b.sh" },
    { "type": "command", "command": "c.sh" }
  ] } ] },
  "statusLine": { "type": "command", "command": "new-statusline.sh" },
  "theme": "dark"
}
JSON

    # Bedrock overlay: SSOT-owned availableModels / modelOverrides.
    cat >"$OVERLAY" <<'JSON'
{
  "_comment": "overlay",
  "availableModels": ["sonnet", "haiku"],
  "modelOverrides": { "opus": "global.anthropic.opus" },
  "model": "global.anthropic.opus"
}
JSON
}

teardown() {
    teardown_isolated_home
}

@test "merge #1088: stale existing.hooks is replaced by SSOT base.hooks" {
    # existing real file: only 1 stale hook, plus a user-edited field.
    cat >"$TGT" <<'JSON'
{
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" }
  ] } ] },
  "model": "user-picked-model",
  "myCustomKey": "keep-me"
}
JSON

    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]

    # SSOT hooks win: all 3 commands present.
    run jq -r '.hooks.SessionStart[0].hooks | length' "$TGT"
    [ "$output" -eq 3 ]
    run jq -r '[.hooks.SessionStart[0].hooks[].command] | join(",")' "$TGT"
    [ "$output" = "a.sh,b.sh,c.sh" ]
}

@test "merge #1088: SSOT statusLine / availableModels / modelOverrides win over stale existing" {
    cat >"$TGT" <<'JSON'
{
  "statusLine": { "type": "command", "command": "OLD-statusline.sh" },
  "availableModels": ["stale-model"],
  "modelOverrides": { "opus": "stale-map" },
  "model": "user-picked-model"
}
JSON

    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]

    run jq -r '.statusLine.command' "$TGT"
    [ "$output" = "new-statusline.sh" ]
    run jq -r '.availableModels | join(",")' "$TGT"
    [ "$output" = "sonnet,haiku" ]
    run jq -r '.modelOverrides.opus' "$TGT"
    [ "$output" = "global.anthropic.opus" ]
}

@test "merge #1088: user-owned fields (model, custom keys) are still preserved" {
    cat >"$TGT" <<'JSON'
{
  "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "a.sh" }
  ] } ] },
  "model": "user-picked-model",
  "theme": "light",
  "myCustomKey": "keep-me"
}
JSON

    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]

    # model is NOT in the SSOT whitelist → existing (user /model choice) wins.
    run jq -r '.model' "$TGT"
    [ "$output" = "user-picked-model" ]
    # arbitrary user key survives.
    run jq -r '.myCustomKey' "$TGT"
    [ "$output" = "keep-me" ]
    # existing overrides base for non-whitelisted scalar (theme).
    run jq -r '.theme' "$TGT"
    [ "$output" = "light" ]
}

@test "merge #1130: values equal but key order differs → Preserved, no backup churn" {
    # Seed TGT via one real merge so it becomes the merge fixed point.
    cat >"$TGT" <<'JSON'
{
  "model": "user-picked-model",
  "theme": "light",
  "myCustomKey": "keep-me"
}
JSON
    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]

    # Rewrite TGT with IDENTICAL values but a different (sorted) key order —
    # this is the real-world churn trigger. jq `*` re-orders keys, so a byte
    # comparison (cmp -s) always saw a "change" and re-wrote + backed up on
    # every re-run even though nothing drifted (issue #1130).
    jq -S . "$TGT" >"$TGT.sorted"
    mv "$TGT.sorted" "$TGT"
    # Drop the backup produced by the seeding merge above — we only want to
    # observe whether the SECOND (idempotent) run creates one.
    rm -f "$TEST_TEMP_HOME"/settings.json.bedrock-merge-backup.*

    # Capture which branch the idempotent re-run takes.
    ux_success() { echo "SUCCESS: $*"; }
    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Preserved (already up to date)"* ]]
    [[ "$output" != *"Merged Bedrock keys into"* ]]

    # No new backup file created on the idempotent run.
    run bash -c 'ls "$1"/settings.json.bedrock-merge-backup.* 2>/dev/null | wc -l' _ "$TEST_TEMP_HOME"
    [ "$output" -eq 0 ]
}

@test "merge #1130: real value drift still Merges + creates one backup" {
    # existing lacks the SSOT-owned fields → a genuine merge is required.
    cat >"$TGT" <<'JSON'
{
  "model": "user-picked-model",
  "theme": "light"
}
JSON
    ux_success() { echo "SUCCESS: $*"; }
    run _merge_claude_settings_json "$BASE" "$OVERLAY" "$TGT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Merged Bedrock keys into"* ]]
    [[ "$output" != *"Preserved (already up to date)"* ]]

    run bash -c 'ls "$1"/settings.json.bedrock-merge-backup.* 2>/dev/null | wc -l' _ "$TEST_TEMP_HOME"
    [ "$output" -eq 1 ]
}
