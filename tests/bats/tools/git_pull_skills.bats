#!/usr/bin/env bats
# tests/bats/tools/git_pull_skills.bats
# Validate git-pull-skills.sh: syntax, options, and repo synchronization.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "git-pull-skills.sh passes bash syntax check" {
    run bash -n "$SCRIPT_UNDER_TEST"
    assert_success
}

@test "git-pull-skills.sh --help displays usage" {
    run bash "$SCRIPT_UNDER_TEST" --help
    assert_success
    assert_output --partial "Usage: git-pull-skills.sh"
    assert_output --partial "--dry-run"
    assert_output --partial "--target"
}

@test "git-pull-skills.sh fails gracefully on missing target" {
    run bash "$SCRIPT_UNDER_TEST" --target "/nonexistent_path_12345"
    assert_failure
    assert_output --partial "Target directory does not exist"
}

@test "git-pull-skills.sh synchronizes out-of-date git repository" {
    local test_skills_dir="${TEST_TEMP_HOME}/skills"
    mkdir -p "$test_skills_dir"

    # Setup remote bare repo
    local remote_repo="${TEST_TEMP_HOME}/remote.git"
    git init --bare "$remote_repo" >/dev/null 2>&1

    # Setup upstream clone to push initial commit
    local upstream_clone="${TEST_TEMP_HOME}/upstream"
    git clone "$remote_repo" "$upstream_clone" >/dev/null 2>&1
    (
        cd "$upstream_clone"
        git checkout -b main >/dev/null 2>&1
        echo "v1" > file.txt
        git config user.name "Test"
        git config user.email "test@example.com"
        git add file.txt
        git commit -m "commit 1" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    # Setup local clone inside test_skills_dir
    local local_repo="${test_skills_dir}/sample-skill"
    git clone -b main "$remote_repo" "$local_repo" >/dev/null 2>&1
    (
        cd "$local_repo"
        git config user.name "Test"
        git config user.email "test@example.com"
    )

    # Push commit 2 to remote
    (
        cd "$upstream_clone"
        echo "v2" > file.txt
        git commit -am "commit 2" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    # Dry-run check
    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir" --dry-run
    assert_success
    assert_output --partial "sample-skill: updates available from origin/main (dry-run)"
    assert_output --partial "Updates available: 1"

    # Verify local file is still v1
    [ "$(cat "${local_repo}/file.txt")" = "v1" ]

    # Real run
    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir"
    assert_success
    assert_output --partial "sample-skill: updated via ff-only (main)"
    assert_output --partial "Updated: 1"

    # Verify local file is now v2
    [ "$(cat "${local_repo}/file.txt")" = "v2" ]
}

@test "git-pull-skills.sh skips dirty repository" {
    local test_skills_dir="${TEST_TEMP_HOME}/skills"
    mkdir -p "$test_skills_dir"

    local remote_repo="${TEST_TEMP_HOME}/remote.git"
    git init --bare "$remote_repo" >/dev/null 2>&1

    local local_repo="${test_skills_dir}/dirty-skill"
    git clone "$remote_repo" "$local_repo" >/dev/null 2>&1
    (
        cd "$local_repo"
        git checkout -b main >/dev/null 2>&1
        git config user.name "Test"
        git config user.email "test@example.com"
        echo "v1" > file.txt
        git add file.txt
        git commit -m "commit 1" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
        echo "dirty changes" >> file.txt
    )

    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir"
    assert_success
    assert_output --partial "dirty-skill: dirty working tree on 'main' (skipped)"
    assert_output --partial "Skipped (dirty): 1"
}
