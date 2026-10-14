#!/usr/bin/env bats
# tests/bats/git/test_hooks_graphify.bats
#
# Hook integration cases: graphify refresh on default-branch pulls (#1838).
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

@test "test_graphify_ff_pull_on_default_branch" {
    test_graphify_ff_pull_on_default_branch
}

@test "test_graphify_rebase_pull_on_default_branch" {
    test_graphify_rebase_pull_on_default_branch
}

@test "test_graphify_ff_rebase_on_default_branch" {
    test_graphify_ff_rebase_on_default_branch
}

@test "test_graphify_replay_rebase_refreshes_once" {
    test_graphify_replay_rebase_refreshes_once
}

@test "test_graphify_skips_branch_switch" {
    test_graphify_skips_branch_switch
}

@test "test_graphify_skips_commit_amend" {
    test_graphify_skips_commit_amend
}

@test "test_graphify_skips_non_default_branch" {
    test_graphify_skips_non_default_branch
}

@test "test_graphify_noop_without_graph_json" {
    test_graphify_noop_without_graph_json
}

@test "test_graphify_absent_pull_succeeds" {
    test_graphify_absent_pull_succeeds
}

@test "test_graphify_keeps_project_hook_delegation" {
    test_graphify_keeps_project_hook_delegation
}
