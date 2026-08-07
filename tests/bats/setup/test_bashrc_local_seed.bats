#!/usr/bin/env bats
# tests/bats/setup/test_bashrc_local_seed.bats
# Issue #1290 — bash installer-isolation via ~/.bashrc.local.
#
# Mirrors the zsh pattern from issue #737 / PR #736: installer and hook
# scripts must append their PC-specific absolute paths to ~/.bashrc.local
# (untracked, in $HOME) instead of polluting the tracked SSOT bash/main.bash
# that is symlinked to ~/.bashrc.
#
# Covered here:
#   1. bash/setup.sh seeds ~/.bashrc.local with the header comment.
#   2. Re-running setup.sh never clobbers existing content (idempotent).
#   3. bash/main.bash sources ~/.bashrc.local when present.

load '../test_helper'

setup() {
    setup_isolated_home
    BASH_SETUP="${DOTFILES_ROOT}/bash/setup.sh"
    MAIN_BASH="${DOTFILES_ROOT}/bash/main.bash"
}

teardown() {
    teardown_isolated_home
}

@test "bash/setup.sh: seeds ~/.bashrc.local when missing" {
    [ ! -f "$HOME/.bashrc.local" ]

    run bash "$BASH_SETUP"
    assert_success

    [ -f "$HOME/.bashrc.local" ]
    run cat "$HOME/.bashrc.local"
    assert_output --partial "~/.bashrc.local — PC-specific overrides, NOT tracked in dotfiles."
    assert_output --partial "issue #1290"
}

@test "bash/setup.sh: logs the seed creation on first run" {
    run bash "$BASH_SETUP"
    assert_success
    assert_output --partial ".bashrc.local 생성"
}

@test "bash/setup.sh: re-run does not clobber existing ~/.bashrc.local" {
    printf '%s\n' '# my custom PC-specific override' \
        'export MY_LOCAL_MARKER=1' >"$HOME/.bashrc.local"

    run bash "$BASH_SETUP"
    assert_success
    # No seed log the second time around — the file already exists.
    refute_output --partial ".bashrc.local 생성"

    run cat "$HOME/.bashrc.local"
    assert_output --partial "# my custom PC-specific override"
    assert_output --partial "export MY_LOCAL_MARKER=1"
    # The seed header must NOT have been appended/prepended.
    refute_output --partial "NOT tracked in dotfiles"
}

@test "bash/setup.sh: two consecutive runs keep the seeded file intact" {
    run bash "$BASH_SETUP"
    assert_success
    first="$(cat "$HOME/.bashrc.local")"

    run bash "$BASH_SETUP"
    assert_success
    second="$(cat "$HOME/.bashrc.local")"

    [ "$first" = "$second" ]
}

@test "bash/main.bash: sources ~/.bashrc.local" {
    # Static check — main.bash carries interactive guards and heavy module
    # loading, so a structural grep is the least fragile assertion here.
    run grep -Fx '[ -f "$HOME/.bashrc.local" ] && source "$HOME/.bashrc.local"' "$MAIN_BASH"
    assert_success
}

@test "bash/main.bash: the local-override hook references issue #1290" {
    run grep -n "issue #1290\|Issue #1290" "$MAIN_BASH"
    assert_success
}
