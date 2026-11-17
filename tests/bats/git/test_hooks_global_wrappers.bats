#!/usr/bin/env bats
# tests/bats/git/test_hooks_global_wrappers.bats
#
# Hook integration cases: global wrapper delegation for pre-push and friends (#1664).
# Case bodies live in hook_cases.bash (moved from git/tests/test_hooks.sh,
# #2163); one @test per case.

load '../test_helper'
load 'hook_test_env'
load 'hook_cases'

setup() {
    hook_test_setup
}

teardown() {
    hook_test_teardown
}

@test "test_global_hook_set_matches_ssot" {
    test_global_hook_set_matches_ssot
}

@test "test_global_pre_push_delegates_to_project_hook" {
    test_global_pre_push_delegates_to_project_hook
}

@test "test_global_pre_push_is_noop_in_unrelated_repo" {
    test_global_pre_push_is_noop_in_unrelated_repo
}

@test "test_global_pre_push_delegates_from_linked_worktree" {
    test_global_pre_push_delegates_from_linked_worktree
}

@test "test_global_wrappers_delegate_argv" {
    test_global_wrappers_delegate_argv
}

@test "test_global_wrappers_propagate_exit_code" {
    test_global_wrappers_propagate_exit_code
}

@test "test_global_wrappers_are_noop_without_project_hook" {
    test_global_wrappers_are_noop_without_project_hook
}

@test "test_global_wrappers_are_noop_outside_git_repo" {
    test_global_wrappers_are_noop_outside_git_repo
}

@test "pre-merge-commit runs through global hooksPath during a merge" {
    local repo="$TEST_TEMP_HOME/merge-repo" hooks="$TEST_TEMP_HOME/global-hooks"
    make_plain_repo "$repo"
    mkdir -p "$hooks" "$repo/scripts/hooks"
    ln -s "$GLOBAL_HOOKS_DIR/pre-merge-commit" "$hooks/pre-merge-commit"
    git -C "$repo" config core.hooksPath "$hooks"
    git -C "$repo" checkout -qb feature
    printf 'feature\n' >"$repo/feature"
    git -C "$repo" add feature
    git -C "$repo" commit -qm feature
    git -C "$repo" checkout -q -
    printf 'main\n' >"$repo/main-file"
    git -C "$repo" add main-file
    git -C "$repo" commit -qm main
    printf '#!/bin/sh\nprintf "PMC-RAN\\n" >&2\n' >"$repo/scripts/hooks/pre-merge-commit"
    chmod +x "$repo/scripts/hooks/pre-merge-commit"
    run git -C "$repo" merge --no-ff -m merge feature
    assert_success
    assert_output --partial 'PMC-RAN'
}

@test "pre-merge-commit forwards stdin to the project hook" {
    local repo="$TEST_TEMP_HOME/stdin-repo"
    make_plain_repo "$repo"
    mkdir -p "$repo/scripts/hooks"
    printf '#!/bin/sh\ncat > "%s/stdin-captured"\n' "$repo" >"$repo/scripts/hooks/pre-merge-commit"
    chmod +x "$repo/scripts/hooks/pre-merge-commit"
    run_global_hook "$repo" pre-merge-commit <<<"hook input"
    [ "$(cat "$repo/stdin-captured")" = 'hook input' ]
}
