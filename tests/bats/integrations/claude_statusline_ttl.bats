#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_ttl.bats
#
# claude/statusline-command.sh (#1385): renders a ⏱️ segment showing the
# current session's prompt cache TTL, read directly from
# $ENABLE_PROMPT_CACHING_1H (claude/settings.json's env block) rather than
# from the stdin payload. "1" -> 1h, anything else (unset/"0"/other) ->
# Claude Code's true default of 5m. It joins the
# existing usage_group (📥💰📤📜) instead of opening a new ┊ group, and unlike
# cost_info it is never gated by SETUP_MODE — the TTL setting applies to
# every account/PC alike.

load '../test_helper'

setup() {
    setup_isolated_home
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
}

teardown() {
    teardown_isolated_home
}

@test "statusline ttl: unset env renders ⏱️ 5m (Claude Code default)" {
    unset ENABLE_PROMPT_CACHING_1H
    _render '{}'
    assert_success
    assert_output --partial '⏱️ 5m'
}

@test "statusline ttl: ENABLE_PROMPT_CACHING_1H=1 renders ⏱️ 1h" {
    export ENABLE_PROMPT_CACHING_1H=1
    _render '{}'
    assert_success
    assert_output --partial '⏱️ 1h'
    refute_output --partial '⏱️ 5m'
}

@test "statusline ttl: joins usage_group right after ctx_info, no new separator" {
    export ENABLE_PROMPT_CACHING_1H=1
    _render_plain '{"context_window":{"used_percentage":11}}'
    assert_success
    assert_output --partial '11% ⏱️ 1h'
    refute_output --partial '11% ┊ ⏱️'
}
