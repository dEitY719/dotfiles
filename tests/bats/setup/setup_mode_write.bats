#!/usr/bin/env bats
# tests/bats/setup/setup_mode_write.bats
# shell-common/setup.sh main() persists ~/.dotfiles-setup-mode right after the
# menu selection. It used to write at the END of each branch under `set -e`,
# so a mid-run failure kept the OLD mode and the next shell/setup defaulted to
# the wrong environment.

load '../test_helper'

setup() {
    setup_isolated_home
    FX="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$FX/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" "$FX/shell-common/"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" "$FX/shell-common/tools/ux_lib/"
}

teardown() {
    teardown_isolated_home
}

# Run main() with <choice> on stdin; the first step fails like a broken sudo/apt.
run_main_first_step_fails() {
    run bash --noprofile --norc -c "
        cd '$FX/shell-common'
        . './setup.sh'
        cleanup_local_files() { return 1; }
        printf '%s\n' '$1' | main
    "
}

@test "mode is written before the steps: a failing step still leaves the new mode" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    run_main_first_step_fails 3
    assert_failure
    run cat "$HOME/.dotfiles-setup-mode"
    assert_output "external"
}

@test "each choice writes its symbolic mode" {
    for pair in 1:public 2:internal 3:external; do
        run_main_first_step_fails "${pair%%:*}"
        run cat "$HOME/.dotfiles-setup-mode"
        assert_output "${pair#*:}"
    done
}

@test "invalid choice keeps the existing mode file untouched" {
    echo internal >"$HOME/.dotfiles-setup-mode"
    run_main_first_step_fails 9
    assert_failure
    assert_output --partial "Invalid choice"
    run cat "$HOME/.dotfiles-setup-mode"
    assert_output "internal"
}
