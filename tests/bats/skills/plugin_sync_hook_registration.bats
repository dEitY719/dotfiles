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

@test "PostToolUse/Bash registers exactly the dispatcher (#1144)" {
    # #1144: the two independent handlers are no longer registered directly —
    # a single thin dispatcher fronts them, halving the common-path spawn.
    run jq -e '
        [.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[]] as $h
        | ($h | length) == 1
          and ($h[0].command | endswith("claude/hooks/post-bash-dispatch.sh"))
    ' "$SETTINGS"
    assert_success
}

@test "PostToolUse/Bash no longer registers the handlers directly (#1144)" {
    # The handlers stay standalone on disk but are reached via the dispatcher,
    # not via their own PostToolUse:Bash registration.
    run jq -e '
        [.hooks.PostToolUse[]
            | select(.matcher == "Bash")
            | .hooks[].command
            | select(endswith("post-gh-pr-create.sh") or endswith("plugin-sync.sh"))]
        | length == 0
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
