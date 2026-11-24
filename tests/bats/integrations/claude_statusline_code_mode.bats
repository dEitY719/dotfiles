#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_code_mode.bats
#
# claude/statusline-command.sh: renders a standalone "🧪 code" group, joined by
# the dim ┊ like every other group, only when
# $CLAUDE_CODE_EXPERIMENTAL_CODE_MODE is exactly "1" (claude/settings.json's env
# block). The stdin payload carries no Code Mode field, so the env var is the
# only signal; unset/"0"/other renders nothing and leaves no dangling ┊.

load '../test_helper'

setup() {
    setup_isolated_home
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
}

teardown() {
    teardown_isolated_home
}

@test "statusline code mode: unset env renders no 🧪 group" {
    unset CLAUDE_CODE_EXPERIMENTAL_CODE_MODE
    _render_plain '{}'
    assert_success
    refute_output --partial '🧪'
}

@test "statusline code mode: =0 renders no 🧪 group" {
    export CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=0
    _render_plain '{}'
    assert_success
    refute_output --partial '🧪'
}

@test "statusline code mode: =1 renders '🧪 code' as its own ┊ group" {
    export CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1
    _render_plain '{}'
    assert_success
    assert_output --partial '┊ 🧪 code'
}

@test "statusline code mode: never leaves a doubled or trailing ┊" {
    export CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1
    _render_plain '{}'
    assert_success
    refute_output --partial '┊ ┊'
    refute_output --regexp '┊ *$'
}
