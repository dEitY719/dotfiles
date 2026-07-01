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
