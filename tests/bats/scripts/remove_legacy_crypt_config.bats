#!/usr/bin/env bats
# tests/bats/scripts/remove_legacy_crypt_config.bats
# The temporary setup.sh cleanup deletes the legacy filter sections from local
# git config and always exits 0 (#2345).
#
# The script derives DOTFILES_ROOT from its own path, so it runs from a copy
# inside a throwaway repo: this repository's .git/config is never touched.
# The tool name is split on purpose, so only the script itself, setup.sh and
# scripts/README.md hold the literal string while the cleanup lives.

load '../test_helper'

setup() {
    setup_isolated_home
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

    TOOL="git""-crypt"
    SCRIPT_NAME="remove-${TOOL}-local-config.sh"
    REAL_ROOT="$DOTFILES_ROOT"
    REPO="$TEST_TEMP_HOME/repo"

    git init -q "$REPO"
    mkdir -p "$REPO/scripts" "$REPO/shell-common/tools"
    cp "$REAL_ROOT/scripts/$SCRIPT_NAME" "$REPO/scripts/"
    cp -R "$REAL_ROOT/shell-common/tools/ux_lib" "$REPO/shell-common/tools/"
}

teardown() {
    teardown_isolated_home
}

_seed_sections() {
    git -C "$REPO" config "filter.$TOOL.smudge" cat
    git -C "$REPO" config "filter.$TOOL.clean" cat
    git -C "$REPO" config "filter.$TOOL.required" false
    git -C "$REPO" config "diff.$TOOL.textconv" cat
}

_run_script() {
    run bash "$REPO/scripts/$SCRIPT_NAME"
}

_assert_sections_gone() {
    run git -C "$REPO" config --local --get-regexp "$TOOL"
    assert_failure
    assert_output ""
}

@test "deletes both sections and leaves other config alone" {
    _seed_sections
    git -C "$REPO" config filter.lfs.clean "git-lfs clean -- %f"

    _run_script
    assert_success
    _assert_sections_gone

    run git -C "$REPO" config filter.lfs.clean
    assert_success
    assert_output "git-lfs clean -- %f"
}

@test "a second run still exits 0" {
    _seed_sections
    _run_script
    assert_success

    _run_script
    assert_success
    _assert_sections_gone
}

@test "exits 0 when neither section exists" {
    _run_script
    assert_success
    _assert_sections_gone
}

@test "deletes one section when the other is absent" {
    git -C "$REPO" config "diff.$TOOL.textconv" cat

    _run_script
    assert_success
    _assert_sections_gone
}

@test "exits 0 outside a git repo" {
    cp -R "$REPO/scripts" "$REPO/shell-common" "$TEST_TEMP_HOME/"
    run bash "$TEST_TEMP_HOME/scripts/$SCRIPT_NAME"
    assert_success
    assert_output --partial "skipped"
}

@test "warns but exits 0 when the config cannot be rewritten" {
    _seed_sections
    : >"$REPO/.git/config.lock"

    _run_script
    assert_success
    assert_output --partial "still set"
}
