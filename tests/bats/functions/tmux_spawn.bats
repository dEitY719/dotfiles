#!/usr/bin/env bats
# tests/bats/functions/tmux_spawn.bats
# Test tmux spawn utility functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: tmux_spawn function exists" {
    run_in_bash 'declare -f tmux_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: tmux_teardown function exists" {
    run_in_bash 'declare -f tmux_teardown >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: tmux-spawn alias exists" {
    run_in_bash 'alias tmux-spawn'
    assert_success
}

@test "bash: tmux-teardown alias exists" {
    run_in_bash 'alias tmux-teardown'
    assert_success
}

@test "zsh: tmux_spawn function exists" {
    run_in_zsh 'declare -f tmux_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}
