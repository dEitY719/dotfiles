#!/usr/bin/env bats
# tests/bats/functions/obsidian_cli.bats
# Test the unified `obsidian` command (issue #1023).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: obsidian function exists" {
    run_in_bash 'declare -f obsidian >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: obsidian -h shows wrapper help" {
    run_in_bash 'obsidian -h'
    assert_success
    assert_output --partial "obsidian"
    assert_output --partial "Usage"
}

@test "bash: OBSIDIAN_CLI_BIN override is honored" {
    run_in_bash 'OBSIDIAN_CLI_BIN=/tmp/custom/Obsidian.com _obsidian_resolve_cli_bin'
    assert_success
    assert_output "/tmp/custom/Obsidian.com"
}

@test "bash: default WSL redirector path" {
    run_in_bash 'unset OBSIDIAN_CLI_BIN; _obsidian_resolve_cli_bin'
    assert_success
    assert_output --partial "/mnt/c/Program Files/Obsidian/Obsidian.com"
}

@test "bash: OBSIDIAN_BIN override resolves AppImage" {
    run_in_bash 'OBSIDIAN_BIN=/tmp/My.AppImage _obsidian_resolve_appimage_bin'
    assert_success
    assert_output "/tmp/My.AppImage"
}

@test "bash: missing WSL redirector returns 127 with guidance" {
    run_in_bash 'WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN=/no/such/Obsidian.com obsidian search query=x'
    assert_failure 127
    assert_output --partial "CLI redirector not found"
}

@test "zsh: obsidian function exists" {
    run_in_zsh 'declare -f obsidian >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: obsidian -h shows wrapper help" {
    run_in_zsh 'obsidian -h'
    assert_success
    assert_output --partial "Usage"
}

@test "zsh: OBSIDIAN_CLI_BIN override is honored" {
    run_in_zsh 'OBSIDIAN_CLI_BIN=/tmp/custom/Obsidian.com _obsidian_resolve_cli_bin'
    assert_success
    assert_output "/tmp/custom/Obsidian.com"
}
