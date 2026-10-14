#!/usr/bin/env bats
# tests/bats/setup/run_module_setup.bats
# Issue #2142 — self-test of the run_module_setup harness in test_helper.bash:
# it must pass an idempotent script (seeing the seeded mode) and fail one that
# rewrites $HOME on every run or exits non-zero.

load '../test_helper'

setup() {
    setup_isolated_home
    FIX="$BATS_TEST_TMPDIR/setup.sh"
}

teardown() {
    teardown_isolated_home
}

fixture() {
    printf '#!/bin/sh\n%s\n' "$1" >"$FIX"
    chmod +x "$FIX"
}

@test "passes a script that converges on the 1st run" {
    fixture '[ -f "$HOME/.seen" ] || echo "mode=$DOTFILES_SETUP_MODE" >"$HOME/.seen"'
    run_module_setup "$FIX" internal
    [ "$(cat "$HOME/.seen")" = "mode=internal" ]
    [ "$(cat "$HOME/.dotfiles-setup-mode")" = internal ]
}

@test "fails a script that rewrites \$HOME on every run" {
    fixture 'date +%s%N >"$HOME/.stamp"'
    run run_module_setup "$FIX"
    assert_failure
    assert_output --partial "2nd run changed"
}

@test "fails a script that exits non-zero" {
    fixture 'exit 3'
    run run_module_setup "$FIX"
    assert_failure
    assert_output --partial "1st run exit 3"
}
