#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_safety.bats
# Verify the Layer-1 ABSOLUTE_BLOCK_PATTERNS documented in
#   claude/skills/gh-issue-proceed/references/safety-gates.md §4.1
# Source-of-truth fixture: _fixtures/gh_issue_proceed_safety.sh
#
# One positive (blocked, rc=2) + one negative (ok, rc=0) per pattern.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh"
}

teardown() {
    teardown_isolated_home
    unset FAKE_DEFAULT_BRANCH FAKE_ME FAKE_ISSUE_CLOSED_BY
}

# ---------- gh pr merge ----------

@test "safety: 'gh pr merge' → blocked gh_pr_merge" {
    run gh_proceed_check_absolute_block "gh pr merge 5 --squash"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: gh_pr_merge'
}

@test "safety: 'gh pr view' → ok" {
    run gh_proceed_check_absolute_block "gh pr view 5"
    assert_success
    assert_output 'ok'
}

# ---------- branch deletion ----------

@test "safety: 'git branch -D feature' → blocked branch_deletion" {
    run gh_proceed_check_absolute_block "git branch -D feature"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: branch_deletion'
}

@test "safety: remote delete push 'git push origin :feature' → blocked branch_deletion" {
    run gh_proceed_check_absolute_block "git push origin :feature"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: branch_deletion'
}

@test "safety: 'git branch feature' (create) → ok" {
    run gh_proceed_check_absolute_block "git branch feature"
    assert_success
    assert_output 'ok'
}

# ---------- force push to default ----------

@test "safety: 'git push --force origin main' → blocked force_push_default" {
    run gh_proceed_check_absolute_block "git push --force origin main"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: force_push_default'
}

@test "safety: 'git push origin main' (no force) → ok" {
    run gh_proceed_check_absolute_block "git push origin main"
    assert_success
    assert_output 'ok'
}

# ---------- force push general ----------

@test "safety: 'git push -f origin feature' → blocked force_push_general" {
    run gh_proceed_check_absolute_block "git push -f origin feature"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: force_push_general'
}

@test "safety: 'git push --force-with-lease origin feature' → ok (Layer 2 gate)" {
    run gh_proceed_check_absolute_block "git push --force-with-lease origin feature"
    assert_success
    assert_output 'ok'
}

# ---------- rm -rf outside pwd ----------

@test "safety: 'rm -rf /etc/app' → blocked rm_rf_outside_pwd" {
    run gh_proceed_check_absolute_block "rm -rf /etc/app"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: rm_rf_outside_pwd'
}

@test "safety: 'rm -rf ./build' (inside pwd) → ok" {
    run gh_proceed_check_absolute_block "rm -rf ./build"
    assert_success
    assert_output 'ok'
}

# ---------- destructive db ----------

@test "safety: 'DROP TABLE users' → blocked destructive_db" {
    run gh_proceed_check_absolute_block 'psql -c "DROP TABLE users"'
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: destructive_db'
}

@test "safety: 'SELECT * FROM users' → ok" {
    run gh_proceed_check_absolute_block 'psql -c "SELECT * FROM users"'
    assert_success
    assert_output 'ok'
}

# ---------- secret in output ----------

@test "safety: 'AWS_SECRET=abc123' → blocked secret_in_output" {
    run gh_proceed_check_absolute_block "echo AWS_SECRET=abc123"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: secret_in_output'
}

@test "safety: 'echo hello world' → ok" {
    run gh_proceed_check_absolute_block "echo hello world"
    assert_success
    assert_output 'ok'
}

# ---------- cross-worktree mutation ----------

@test "safety: 'git -C /other/wt commit' → blocked cross_worktree_mutation" {
    run gh_proceed_check_absolute_block "git -C /other/wt commit -m x"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: cross_worktree_mutation'
}

@test "safety: 'git commit -m x' (current tree) → ok" {
    run gh_proceed_check_absolute_block "git commit -m x"
    assert_success
    assert_output 'ok'
}

# ---------- reopen foreign-closed issue ----------

@test "safety: reopen issue closed by another user → blocked reopen_foreign_closed" {
    FAKE_ME="alice"
    FAKE_ISSUE_CLOSED_BY="bob"
    run gh_proceed_check_absolute_block "gh issue reopen 5"
    [ "$status" -eq 2 ]
    assert_output --partial 'blocked: reopen_foreign_closed'
}

@test "safety: reopen issue closed by self → ok" {
    FAKE_ME="alice"
    FAKE_ISSUE_CLOSED_BY="alice"
    run gh_proceed_check_absolute_block "gh issue reopen 5"
    assert_success
    assert_output 'ok'
}
