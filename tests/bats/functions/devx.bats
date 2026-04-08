#!/usr/bin/env bats
# tests/bats/functions/devx.bats
# Test devx development helper function.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: devx function exists" {
    run_in_bash 'declare -f devx >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: devx with no args shows usage and exits non-zero" {
    run_in_bash 'devx'
    assert_failure
}

@test "bash: devx --help shows usage" {
    run_in_bash 'devx --help'
    assert_success
}

@test "bash: devx in dir without dev.sh exits with error" {
    run_in_bash "cd '${HOME}' && devx run 2>&1"
    assert_failure
}

@test "zsh: devx function exists" {
    run_in_zsh 'declare -f devx >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}
