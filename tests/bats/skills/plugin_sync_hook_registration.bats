#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook_registration.bats
# claude/settings.json에 plugin-sync.sh가 PostToolUse/Bash로 등록됐는지,
# 기존 post-gh-pr-create.sh 등록이 안 깨졌는지 확인.

load '../test_helper'

SETTINGS="${_BATS_REAL_DOTFILES_ROOT}/claude/settings.json"

@test "settings.json is valid JSON" {
    run jq -e '.' "$SETTINGS"
    assert_success
}

@test "PostToolUse/Bash includes plugin-sync.sh" {
    run jq -e '
        .hooks.PostToolUse[]
        | select(.matcher == "Bash")
        | .hooks[]
        | select(.command | endswith("claude/hooks/plugin-sync.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "PostToolUse/Bash still includes post-gh-pr-create.sh" {
    run jq -e '
        .hooks.PostToolUse[]
        | select(.matcher == "Bash")
        | .hooks[]
        | select(.command | endswith("claude/hooks/post-gh-pr-create.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "SessionStart includes plugin-sync-session.sh (#1082)" {
    run jq -e '
        .hooks.SessionStart[].hooks[]
        | select(.command | endswith("claude/hooks/plugin-sync-session.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "Stop includes plugin-sync-session.sh (#1082)" {
    run jq -e '
        .hooks.Stop[].hooks[]
        | select(.command | endswith("claude/hooks/plugin-sync-session.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "SessionStart still includes session-start-pc-context.sh" {
    run jq -e '
        .hooks.SessionStart[].hooks[]
        | select(.command | endswith("claude/hooks/session-start-pc-context.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "SessionStart includes session-start-plugin-path-normalize.sh (#1098)" {
    run jq -e '
        .hooks.SessionStart[].hooks[]
        | select(.command | endswith("claude/hooks/session-start-plugin-path-normalize.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "path-normalize runs BEFORE plugin-sync-session in SessionStart (#1098)" {
    # The normalizer must re-stamp installLocation before plugin-sync-session
    # snapshots its baseline, else the baseline captures stale spellings.
    run jq -e '
        .hooks.SessionStart[].hooks
        | (map(.command | endswith("session-start-plugin-path-normalize.sh")) | index(true))
          < (map(.command | endswith("plugin-sync-session.sh")) | index(true))
    ' "$SETTINGS"
    assert_success
}
