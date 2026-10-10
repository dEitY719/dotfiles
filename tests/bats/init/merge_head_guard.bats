#!/usr/bin/env bats
# tests/bats/init/merge_head_guard.bats
# Shell-startup diagnostic for an abandoned `git sync` merge (#2078).
# The fake tree has no shell-common, so everything after the guard fails —
# which is the point: the diagnostic must print before any module is sourced.

load '../test_helper'

MSG='dotfiles 머지 미완(.git/MERGE_HEAD 존재)'

setup() {
    setup_isolated_home
    FAKE="$TEST_TEMP_HOME/fake-dotfiles"
    mkdir -p "$FAKE/bash" "$FAKE/zsh" "$FAKE/.git"
    cp "$_BATS_REAL_DOTFILES_ROOT/bash/main.bash" "$FAKE/bash/main.bash"
    cp "$_BATS_REAL_DOTFILES_ROOT/zsh/main.zsh" "$FAKE/zsh/main.zsh"
}

teardown() {
    teardown_isolated_home
}

_bash_i() { run bash --noprofile --norc -i -c ". '$FAKE/bash/main.bash'" 2>&1; }
_zsh_i() {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -i -c "DOTFILES_ROOT='$FAKE'; . '$FAKE/zsh/main.zsh'" 2>&1
}

@test "bash: MERGE_HEAD present prints diagnostic before module sourcing" {
    : >"$FAKE/.git/MERGE_HEAD"
    _bash_i
    [[ "$output" == *"$MSG"* ]]
}

@test "bash: MERGE_HEAD absent prints no diagnostic" {
    _bash_i
    [[ "$output" != *"$MSG"* ]]
}

@test "bash: non-interactive shell prints no diagnostic" {
    : >"$FAKE/.git/MERGE_HEAD"
    run env -u DOTFILES_FORCE_INIT bash --noprofile --norc -c ". '$FAKE/bash/main.bash'" 2>&1
    [[ "$output" != *"$MSG"* ]]
}

@test "zsh: MERGE_HEAD present prints diagnostic before module sourcing" {
    : >"$FAKE/.git/MERGE_HEAD"
    _zsh_i
    [[ "$output" == *"$MSG"* ]]
}

@test "zsh: MERGE_HEAD absent prints no diagnostic" {
    _zsh_i
    [[ "$output" != *"$MSG"* ]]
}

@test "zsh: non-interactive shell prints no diagnostic" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    : >"$FAKE/.git/MERGE_HEAD"
    run zsh -f -c "DOTFILES_ROOT='$FAKE'; . '$FAKE/zsh/main.zsh'" 2>&1
    [[ "$output" != *"$MSG"* ]]
}
