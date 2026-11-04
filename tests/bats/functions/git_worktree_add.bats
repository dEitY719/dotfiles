#!/usr/bin/env bats
# tests/bats/functions/git_worktree_add.bats
# git_worktree_add (#2345) is a plain `git worktree add`: every tracked file is
# checked out and core.sparseCheckout stays unset, in all three argument forms
# and in both shells. Runs against a mktemp fixture repo only.

load '../test_helper'

setup() {
    setup_isolated_home
    FIXTURE="$(mktemp -d)"
    REPO="$FIXTURE/repo"
    mkdir -p "$REPO/sub"
    printf 'a\n' >"$REPO/a.txt"
    printf 'b\n' >"$REPO/sub/b.txt"
    git -C "$REPO" init -q -b main
    git -C "$REPO" add -A
    git -C "$REPO" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t \
        commit -qm fixture
}

teardown() {
    cd /
    [ -n "$FIXTURE" ] && rm -rf "$FIXTURE"
    teardown_isolated_home
}

# $1 = worktree path; asserts full checkout and no sparse-checkout.
_assert_full_checkout() {
    [ -f "$1/a.txt" ]
    [ -f "$1/sub/b.txt" ]
    run git -C "$1" config --get core.sparseCheckout
    assert_output ""
}

@test "bash: gwt add <path> checks out every file without sparse-checkout" {
    run_in_bash "cd '$REPO' && git_worktree_add '$FIXTURE/wt1'"
    assert_success
    assert_output --partial "Worktree ready: $FIXTURE/wt1"
    _assert_full_checkout "$FIXTURE/wt1"
}

@test "bash: gwt add <path> <branch> creates the branch with a full checkout" {
    run_in_bash "cd '$REPO' && git_worktree_add '$FIXTURE/wt2' feat-x"
    assert_success
    assert_output --partial "Worktree ready: $FIXTURE/wt2"
    _assert_full_checkout "$FIXTURE/wt2"
    run git -C "$FIXTURE/wt2" rev-parse --abbrev-ref HEAD
    assert_output "feat-x"
}

@test "bash: gwt add <path> <branch> <start> uses the start point" {
    run_in_bash "cd '$REPO' && git_worktree_add '$FIXTURE/wt3' feat-y main"
    assert_success
    assert_output --partial "Worktree ready: $FIXTURE/wt3"
    _assert_full_checkout "$FIXTURE/wt3"
    run git -C "$FIXTURE/wt3" rev-parse --abbrev-ref HEAD
    assert_output "feat-y"
}

@test "zsh: gwt add <path> <branch> <start> checks out every file without sparse-checkout" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run_in_zsh "cd '$REPO' && git_worktree_add '$FIXTURE/wt4' feat-z main"
    assert_success
    assert_output --partial "Worktree ready: $FIXTURE/wt4"
    _assert_full_checkout "$FIXTURE/wt4"
}
