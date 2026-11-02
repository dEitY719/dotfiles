#!/usr/bin/env bats
# tests/bats/functions/git_worktree_add.bats
# `gwt add` checks out a plain worktree: every argument form yields all tracked
# files and leaves sparse-checkout off (#2345).

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_REPO="$TEST_TEMP_HOME/fake-main"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    git init -q --initial-branch=main "$FAKE_REPO"
    (
        cd "$FAKE_REPO"
        mkdir -p dir/nested
        echo base >base.txt
        echo nested >dir/nested/file.txt
        echo hidden >.hidden
        git add .
        git commit -q -m base
        git branch start-here
        git checkout -q start-here
        echo extra >start-only.txt
        git add start-only.txt
        git commit -q -m extra
        git checkout -q main
    )
    WT_PATH="$TEST_TEMP_HOME/wt"
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# Full checkout + no sparse-checkout state, on top of the function's own output.
_assert_plain_worktree() {
    local rev="$1" expected actual sparse_file
    assert_success
    assert_output --partial "Worktree ready: $WT_PATH"

    expected="$(git -C "$FAKE_REPO" ls-tree -r --name-only "$rev")"
    actual="$(cd "$WT_PATH" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort)"
    assert_equal "$actual" "$(printf '%s\n' "$expected" | LC_ALL=C sort)"

    run git -C "$WT_PATH" config --get core.sparseCheckout
    assert_failure
    run git -C "$FAKE_REPO" config --get extensions.worktreeConfig
    assert_failure
    sparse_file="$(git -C "$WT_PATH" rev-parse --path-format=absolute --git-path info/sparse-checkout)"
    assert_file_not_exists "$sparse_file"
}

assert_file_not_exists() {
    [ ! -e "$1" ] || fail "expected no file at: $1"
}

@test "bash: gwt add <path> checks out everything without sparse-checkout" {
    run_in_bash "cd '$FAKE_REPO' && gwt add '$WT_PATH'"
    _assert_plain_worktree main
}

@test "bash: gwt add <path> <new-branch> checks out everything without sparse-checkout" {
    run_in_bash "cd '$FAKE_REPO' && gwt add '$WT_PATH' feature/one"
    _assert_plain_worktree main
    assert_equal "$(git -C "$WT_PATH" branch --show-current)" "feature/one"
}

@test "bash: gwt add <path> <new-branch> <start-point> starts from the start point" {
    run_in_bash "cd '$FAKE_REPO' && gwt add '$WT_PATH' feature/two start-here"
    _assert_plain_worktree start-here
    assert_equal "$(git -C "$WT_PATH" branch --show-current)" "feature/two"
    assert_equal "$(git -C "$WT_PATH" rev-parse HEAD)" "$(git -C "$FAKE_REPO" rev-parse start-here)"
}

@test "zsh: gwt add <path> checks out everything without sparse-checkout" {
    run_in_zsh "cd '$FAKE_REPO' && gwt add '$WT_PATH'"
    _assert_plain_worktree main
}

@test "zsh: gwt add <path> <new-branch> checks out everything without sparse-checkout" {
    run_in_zsh "cd '$FAKE_REPO' && gwt add '$WT_PATH' feature/one"
    _assert_plain_worktree main
    assert_equal "$(git -C "$WT_PATH" branch --show-current)" "feature/one"
}

@test "zsh: gwt add <path> <new-branch> <start-point> starts from the start point" {
    run_in_zsh "cd '$FAKE_REPO' && gwt add '$WT_PATH' feature/two start-here"
    _assert_plain_worktree start-here
    assert_equal "$(git -C "$WT_PATH" branch --show-current)" "feature/two"
    assert_equal "$(git -C "$WT_PATH" rev-parse HEAD)" "$(git -C "$FAKE_REPO" rev-parse start-here)"
}

@test "bash: gwt add fails and reports nothing ready when git worktree add fails" {
    git -C "$FAKE_REPO" branch taken
    run_in_bash "cd '$FAKE_REPO' && gwt add '$WT_PATH' taken"
    assert_failure
    refute_output --partial "Worktree ready"
}
