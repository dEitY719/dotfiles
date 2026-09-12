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

@test "git-pull-skills.sh syncs dual-remote (origin + upstream) repository" {
    local test_skills_dir="${TEST_TEMP_HOME}/skills"
    mkdir -p "$test_skills_dir"

    local remote_origin="${TEST_TEMP_HOME}/origin.git"
    local remote_upstream="${TEST_TEMP_HOME}/upstream.git"
    git init --bare "$remote_origin" >/dev/null 2>&1
    git init --bare "$remote_upstream" >/dev/null 2>&1

    # Seed upstream with initial commit + upstream commit
    local upstream_work="${TEST_TEMP_HOME}/upstream_work"
    git clone "$remote_upstream" "$upstream_work" >/dev/null 2>&1
    (
        cd "$upstream_work"
        git checkout -b main >/dev/null 2>&1
        git config user.name "Test"
        git config user.email "test@example.com"
        echo "base" > base.txt
        git add base.txt
        git commit -m "base commit" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    # Seed origin from upstream base
    local origin_work="${TEST_TEMP_HOME}/origin_work"
    git clone "$remote_origin" "$origin_work" >/dev/null 2>&1
    (
        cd "$origin_work"
        git checkout -b main >/dev/null 2>&1
        git config user.name "Test"
        git config user.email "test@example.com"
        git remote add upstream "$remote_upstream" >/dev/null 2>&1
        git pull upstream main >/dev/null 2>&1
        echo "origin change" > origin.txt
        git add origin.txt
        git commit -m "origin commit" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    # Add upstream change
    (
        cd "$upstream_work"
        echo "upstream change" > upstream.txt
        git add upstream.txt
        git commit -m "upstream commit" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    # Setup local clone inside test_skills_dir with origin and upstream
    local local_repo="${test_skills_dir}/dual-skill"
    git clone -b main "$remote_origin" "$local_repo" >/dev/null 2>&1
    (
        cd "$local_repo"
        git config user.name "Test"
        git config user.email "test@example.com"
        git remote add upstream "$remote_upstream" >/dev/null 2>&1
    )

    # Test dry-run
    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir" --dry-run
    assert_success
    assert_output --partial "dual-skill: updates available from origin/upstream (main, dry-run)"
    assert_output --partial "Updates available: 1"

    # Test real run
    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir"
    assert_success
    assert_output --partial "dual-skill: synced and pushed to origin (main)"
    assert_output --partial "Updated: 1"

    # Verify local has both changes
    [ -f "${local_repo}/origin.txt" ]
    [ -f "${local_repo}/upstream.txt" ]

    # Verify origin remote received the push
    local check_origin="${TEST_TEMP_HOME}/check_origin"
    git clone -b main "$remote_origin" "$check_origin" >/dev/null 2>&1
    [ -f "${check_origin}/upstream.txt" ]

    # Run again: should be up-to-date
    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir"
    assert_success
    assert_output --partial "dual-skill: up-to-date (origin+upstream: main)"
    assert_output --partial "Up to date: 1"
}

@test "git-pull-skills.sh handles merge conflict in dual-remote repository by aborting" {
    local test_skills_dir="${TEST_TEMP_HOME}/skills"
    mkdir -p "$test_skills_dir"

    local remote_origin="${TEST_TEMP_HOME}/origin_conf.git"
    local remote_upstream="${TEST_TEMP_HOME}/upstream_conf.git"
    git init --bare "$remote_origin" >/dev/null 2>&1
    git init --bare "$remote_upstream" >/dev/null 2>&1

    # Base commit
    local setup_work="${TEST_TEMP_HOME}/setup_conf"
    git clone "$remote_upstream" "$setup_work" >/dev/null 2>&1
    (
        cd "$setup_work"
        git checkout -b main >/dev/null 2>&1
        git config user.name "Test"
        git config user.email "test@example.com"
        echo "original line" > conflict.txt
        git add conflict.txt
        git commit -m "base" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
        git remote add origin_remote "$remote_origin" >/dev/null 2>&1
        git push origin_remote main >/dev/null 2>&1
    )

    # Local repo cloned from origin
    local local_repo="${test_skills_dir}/conflict-skill"
    git clone -b main "$remote_origin" "$local_repo" >/dev/null 2>&1
    (
        cd "$local_repo"
        git config user.name "Test"
        git config user.email "test@example.com"
        git remote add upstream "$remote_upstream" >/dev/null 2>&1
        # Make a commit locally modifying conflict.txt
        echo "local modification" > conflict.txt
        git commit -am "local edit" >/dev/null 2>&1
    )

    # Upstream makes conflicting commit
    (
        cd "$setup_work"
        echo "upstream conflicting edit" > conflict.txt
        git commit -am "upstream conflict" >/dev/null 2>&1
        git push origin main >/dev/null 2>&1
    )

    run bash "$SCRIPT_UNDER_TEST" --target "$test_skills_dir"
    assert_failure
    assert_output --partial "conflict-skill: merge upstream/main failed (conflict)"
    assert_output --partial "Failed: 1"

    # Verify merge was aborted and working tree is clean
    [ -z "$(git -C "$local_repo" status --porcelain)" ]
}

