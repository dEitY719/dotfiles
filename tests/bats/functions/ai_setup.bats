#!/usr/bin/env bats
# tests/bats/functions/ai_setup.bats
# Tests for ai_setup --agent flag (issue #162).
# ai_setup is interactive, so we only exercise the argument-parsing
# preamble that fails fast before the first prompt.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: ai_setup function exists" {
    run_in_bash 'declare -f ai_setup >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: ai-setup --help mentions --agent flag" {
    run_in_bash 'ai_setup --help'
    assert_success
    assert_output --partial "--agent"
}

@test "bash: ai_setup --agent requires an argument" {
    run_in_bash 'ai_setup --agent 2>&1'
    assert_failure
    assert_output --partial "--agent requires an argument"
}

@test "bash: ai_setup --agent rejects unknown agent" {
    run_in_bash 'ai_setup --agent bogus 2>&1'
    assert_failure
    assert_output --partial "Unknown agent: bogus"
}

@test "zsh: ai_setup function exists" {
    run_in_zsh 'declare -f ai_setup >/dev/null && echo ok'
    assert_success
}
