#!/usr/bin/env bats
# tests/bats/functions/test_clean_home.bats
# Tests for the `clean-home` entry point added in issue #806
# (del_file --home + home whitelist + ~/dotfiles-backup/ offer).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: clean-home alias exists" {
    run_in_bash 'alias clean-home'
    assert_success
    assert_output --partial "del_file --home"
}

@test "zsh: clean-home alias exists" {
    run_in_zsh 'alias clean-home'
    assert_success
    assert_output --partial "del_file --home"
}

@test "bash: _cleanup_set_home_patterns covers .backup/.original/.bak" {
    run_in_bash '_cleanup_set_home_patterns; for p in "${CLEANUP_HOME_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial ".backup"
    assert_output --partial "-original"
    assert_output --partial ".bak"
}

@test "zsh: _cleanup_set_home_patterns covers .backup/.original/.bak" {
    run_in_zsh '_cleanup_set_home_patterns; for p in "${CLEANUP_HOME_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial ".backup"
    assert_output --partial "-original"
    assert_output --partial ".bak"
}

@test "bash: dotfiles-backup dir offer is a no-op when dir is absent" {
    run_in_bash '_cleanup_offer_dotfiles_backup_dir "$HOME"; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
}

@test "bash: del_file --help documents --home / clean-home" {
    run_in_bash 'del_file --help'
    assert_success
    assert_output --partial "--home"
    assert_output --partial "clean-home"
}

@test "bash: del_file --home refuses without an interactive terminal" {
    # The test harness pipes stdin (non-tty), so --home must bail out cleanly
    # rather than scan/delete anything.
    run_in_bash 'del_file --home; echo "rc=$?"'
    assert_output --partial "requires an interactive terminal"
    assert_output --partial "rc=1"
}
