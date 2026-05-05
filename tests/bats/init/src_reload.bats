#!/usr/bin/env bats
# tests/bats/init/src_reload.bats
# Verify `src` always reloads from the canonical dotfiles tree, even when
# the inherited shell has DOTFILES_ROOT leaked to a worktree path
# (regression for issue #310).

load '../test_helper'

setup() {
    setup_isolated_home

    # Stub canonical dotfiles tree under the isolated HOME.
    FAKE_CANON="$TEST_TEMP_HOME/fake-canon"
    mkdir -p "$FAKE_CANON/bash" "$FAKE_CANON/zsh" "$FAKE_CANON/shell-common"

    # Stub rc files — `src` only needs them to source successfully.
    : >"$FAKE_CANON/bash/main.bash"
    : >"$FAKE_CANON/zsh/zshrc"

    # Path that simulates a worktree-leaked DOTFILES_ROOT.
    LEAK_ROOT="$TEST_TEMP_HOME/leaked-worktree"
    mkdir -p "$LEAK_ROOT"
}

teardown() {
    teardown_isolated_home
}

# Helper: run `src` in a clean bash subshell with leaked DOTFILES_ROOT
# preset, and capture the resulting environment.
_run_src_bash() {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        export DOTFILES_CANONICAL='$FAKE_CANON'
        export DOTFILES_ROOT='$LEAK_ROOT'
        export SHELL_COMMON='$LEAK_ROOT/shell-common'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/aliases/core.sh'
        src || exit \$?
        printf 'AFTER:DOTFILES_ROOT=%s\n' \"\$DOTFILES_ROOT\"
        printf 'AFTER:SHELL_COMMON=%s\n' \"\$SHELL_COMMON\"
        printf 'AFTER:DOTFILES_BASH_DIR=%s\n' \"\${DOTFILES_BASH_DIR-<unset>}\"
    "
}

_run_src_zsh() {
    run zsh -f -c "
        export HOME='$HOME'
        export DOTFILES_CANONICAL='$FAKE_CANON'
        export DOTFILES_ROOT='$LEAK_ROOT'
        export SHELL_COMMON='$LEAK_ROOT/shell-common'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/aliases/core.sh'
        src || exit \$?
        printf 'AFTER:DOTFILES_ROOT=%s\n' \"\$DOTFILES_ROOT\"
        printf 'AFTER:SHELL_COMMON=%s\n' \"\$SHELL_COMMON\"
    "
}

@test "bash: src resets leaked DOTFILES_ROOT to canonical" {
    _run_src_bash
    assert_success
    assert_output --partial "AFTER:DOTFILES_ROOT=$FAKE_CANON"
    assert_output --partial "AFTER:SHELL_COMMON=$FAKE_CANON/shell-common"
}

@test "bash: src unsets DOTFILES_BASH_DIR before re-sourcing" {
    _run_src_bash
    assert_success
    # Stub main.bash is empty, so DOTFILES_BASH_DIR stays unset after src.
    assert_output --partial "AFTER:DOTFILES_BASH_DIR=<unset>"
}

@test "zsh: src resets leaked DOTFILES_ROOT to canonical" {
    _run_src_zsh
    assert_success
    assert_output --partial "AFTER:DOTFILES_ROOT=$FAKE_CANON"
    assert_output --partial "AFTER:SHELL_COMMON=$FAKE_CANON/shell-common"
}

@test "bash: src fails with non-zero when canonical dir is missing" {
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        export DOTFILES_CANONICAL='$TEST_TEMP_HOME/does-not-exist'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/aliases/core.sh'
        src
    "
    assert_failure
    assert_output --partial "canonical dotfiles not found"
}

@test "bash: src defaults to \$HOME/dotfiles when DOTFILES_CANONICAL is unset" {
    # Stage a fake canonical at $HOME/dotfiles inside the isolated home.
    mkdir -p "$HOME/dotfiles/bash"
    : >"$HOME/dotfiles/bash/main.bash"

    run bash --noprofile --norc -c "
        export HOME='$HOME'
        unset DOTFILES_CANONICAL
        export DOTFILES_ROOT='$LEAK_ROOT'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_DOTFILES_ROOT/shell-common/aliases/core.sh'
        src || exit \$?
        printf 'AFTER:DOTFILES_ROOT=%s\n' \"\$DOTFILES_ROOT\"
    "
    assert_success
    assert_output --partial "AFTER:DOTFILES_ROOT=$HOME/dotfiles"
}
