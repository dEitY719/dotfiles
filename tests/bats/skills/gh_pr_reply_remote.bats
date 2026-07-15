#!/usr/bin/env bats
# tests/bats/skills/gh_pr_reply_remote.bats
# Behavior tests for the `[remote]` positional added to the gh:pr-reply
# skill (issue #1165). The skill's Step 1 resolves TARGET_REPO by parsing
# the named remote's URL via the SSOT helper
# `_gh_pr_review_resolve_target_repo` — NOT via gh's default-repo
# heuristic. These tests prove the remote arg actually selects the repo
# in a multi-remote repo (origin + upstream on the same GitHub host),
# which is the edge case the issue closes.
#
# Reuses the arg-parse fixture (which sources
# shell-common/functions/gh_pr_review.sh — the same file the skill sources)
# so the production resolver is exercised, not a copy.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh"

    # Fake repo with two GitHub remotes on the same host.
    MULTI_REMOTE_REPO="$TEST_TEMP_HOME/multi-remote"
    # No --initial-branch: these tests never reference the branch name, so
    # omitting it keeps the setup working on Git < 2.28.
    git init -q "$MULTI_REMOTE_REPO"
    (
        cd "$MULTI_REMOTE_REPO" || exit 1
        git remote add origin "git@github.com:owner-a/repo-a.git"
        git remote add upstream "https://github.com/owner-b/repo-b.git"
    )
}

teardown() {
    teardown_isolated_home
}

# ---- the remote arg selects the target repo -------------------------------

@test "remote: default (no arg) resolves origin's repo" {
    cd "$MULTI_REMOTE_REPO" || return 1
    run _gh_pr_review_resolve_target_repo
    assert_success
    assert_output "owner-a/repo-a"
}

@test "remote: explicit 'origin' resolves owner-a/repo-a" {
    cd "$MULTI_REMOTE_REPO" || return 1
    run _gh_pr_review_resolve_target_repo origin
    assert_success
    assert_output "owner-a/repo-a"
}

@test "remote: explicit 'upstream' resolves owner-b/repo-b (not origin)" {
    cd "$MULTI_REMOTE_REPO" || return 1
    run _gh_pr_review_resolve_target_repo upstream
    assert_success
    assert_output "owner-b/repo-b"
}

# ---- rejection paths ------------------------------------------------------

@test "remote: unknown remote fails with actionable message + remote list" {
    cd "$MULTI_REMOTE_REPO" || return 1
    run _gh_pr_review_resolve_target_repo does-not-exist
    assert_failure
    assert_output --partial "Remote 'does-not-exist' not found"
}
