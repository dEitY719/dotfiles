#!/usr/bin/env bats
# tests/bats/functions/claude_help_plugin.bats
# claude_help의 신규 `plugin` 섹션 검증.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

_run_claude_help() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/ai_tools_help.sh'
        claude_help $1
    "
}

@test "claude-help --list includes plugin section" {
    run _run_claude_help --list
    assert_success
    assert_output --partial 'plugin'
}

@test "claude-help summary mentions plugin section" {
    run _run_claude_help ""
    assert_success
    assert_output --partial 'plugin'
}

@test "claude-help plugin shows restore.sh usage" {
    run _run_claude_help plugin
    assert_success
    assert_output --partial 'claude/plugin/restore.sh'
    assert_output --partial 'claude plugin marketplace add/remove'
}

@test "claude-help --all renders the plugin section" {
    run _run_claude_help --all
    assert_success
    assert_output --partial 'claude/plugin/restore.sh'
}
