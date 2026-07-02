#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_publish_sync.bats
# claude/plugin/publish-sync.sh — publishes plugin-sync.sh's local-only
# manifest commits to origin (and, on internal PCs, the GHES company/
# repo) via branch + PR + admin-merge, since both repos require PRs.

load '../test_helper'

PUBLISH_SYNC="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/publish-sync.sh"

setup() {
    setup_isolated_home
    source "$PUBLISH_SYNC"
}

teardown() {
    teardown_isolated_home
}

@test "_repo_target parses git@ SSH form" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "git@github.com:dEitY719/dotfiles.git"

    run _repo_target "$REPO"
    assert_success
    assert_output "dEitY719/dotfiles"
}

@test "_repo_target parses https form on a GHES host" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.samsungds.net/byoungwoo-yoon/claude-plugin-jira.git"

    run _repo_target "$REPO"
    assert_success
    assert_output "byoungwoo-yoon/claude-plugin-jira"
}

@test "_repo_target fails when origin remote is missing" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q

    run _repo_target "$REPO"
    assert_failure
}

_seed_repo_with_origin() {
    # $1 = repo dir to create. Sets up repo_dir with an `origin` remote
    # pointing at a local bare repo, one commit on main in both, so tests
    # can freely diverge repo_dir from origin/main.
    local repo_dir="$1"
    local bare="$TEST_TEMP_HOME/origin.git"
    git init -q --bare "$bare"

    mkdir -p "$repo_dir/claude/plugin"
    git -C "$repo_dir" init -q -b main
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "test"
    echo '{}' >"$repo_dir/claude/plugin/marketplaces.json"
    echo '{"plugins": []}' >"$repo_dir/claude/plugin/plugins.json"
    git -C "$repo_dir" add claude/plugin
    git -C "$repo_dir" commit -q -m "seed"
    git -C "$repo_dir" remote add origin "$bare"
    git -C "$repo_dir" push -q origin main
}

@test "_manifest_diff_exists returns false when files match origin/main" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" fetch origin --quiet

    run _manifest_diff_exists "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_failure
}

@test "_manifest_diff_exists returns true when local file changed" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    git -C "$REPO" fetch origin --quiet

    run _manifest_diff_exists "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
}

@test "_build_publish_commit snapshots current file content onto origin/main without touching the real index" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    git -C "$REPO" fetch origin --quiet

    BEFORE_HEAD=$(git -C "$REPO" rev-parse HEAD)
    BEFORE_STATUS=$(git -C "$REPO" status --porcelain)

    run _build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    NEW_COMMIT="$output"

    # parent is origin/main, not the diverged local HEAD
    run git -C "$REPO" rev-parse "${NEW_COMMIT}^"
    assert_output "$(git -C "$REPO" rev-parse origin/main)"

    # tree carries the current (edited) marketplaces.json content
    run git -C "$REPO" show "${NEW_COMMIT}:claude/plugin/marketplaces.json"
    assert_output '{"anthropic-agent-skills": "anthropics/skills"}'

    # real HEAD/index/working tree untouched
    assert_equal "$(git -C "$REPO" rev-parse HEAD)" "$BEFORE_HEAD"
    assert_equal "$(git -C "$REPO" status --porcelain)" "$BEFORE_STATUS"
}
