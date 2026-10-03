#!/usr/bin/env bats
# tests/bats/skills/helper_fallback_nf1.bats
# Smoke test for issue #644 — helper-fallback NF-1.
#
# Verifies the canonical `[ -r ]` guard + `|| true` block applied to all
# helper source points across:
#   gh-pr-merge / gh-pr / gh-pr-reply / gh-pr-merge-emergency / gh-commit
#   (external skill repos since #1680)
# behaves correctly under both helper-present and helper-missing
# (e.g. agent-toolbox / cross-project skill copy) environments.
#
# Acceptance criteria mapped from issue #644:
#   - SHELL_COMMON pointing at an empty dir → no `command not found`,
#     silent skip, calling skill continues.
#   - SHELL_COMMON pointing at a populated dir → helper sourced,
#     _gh_project_status_sync invoked.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/helper_fallback_nf1.sh"
}

teardown() {
    teardown_isolated_home
    unset SHELL_COMMON
}

@test "helper present → block runs sync and continues" {
    local helper_dir="$TEST_TEMP_HOME/sc/functions"
    nf1_install_fake_helper "$helper_dir/gh_project_status.sh"
    export SHELL_COMMON="$TEST_TEMP_HOME/sc"

    run nf1_canonical_block 644 "Done"
    assert_success
    assert_output --partial "BLOCK_RAN sync_called"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "helper missing (SHELL_COMMON=/tmp/empty equivalent) → silent skip, no command-not-found" {
    # NF-1 core guarantee from issue #644: skill body keeps running.
    export SHELL_COMMON="$TEST_TEMP_HOME/empty-sc"
    [ ! -e "$SHELL_COMMON/functions/gh_project_status.sh" ] || {
        echo "precondition violated: fake SHELL_COMMON should not contain helper" >&2
        return 1
    }

    run nf1_canonical_block 644 "Done"
    assert_success
    refute_output --partial "BLOCK_RAN sync_called"
    refute_output --partial "command not found"
    refute_output --partial "_gh_project_status_sync"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "helper missing, SHELL_COMMON unset → fallback path also silent-skips" {
    # When SHELL_COMMON is unset the canonical block falls back to
    # $HOME/dotfiles/shell-common. Under bats isolation HOME is a fresh
    # tmpdir, so that path is absent — the [ -r ] guard must still hold.
    unset SHELL_COMMON

    run nf1_canonical_block 644 "Done"
    assert_success
    refute_output --partial "BLOCK_RAN sync_called"
    refute_output --partial "command not found"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "fixture's helper contract matches this repo's helper (drift guard)" {
    # The canonical F-2 block lives in the external skill repos since #1680
    # (workspace ${WORKSPACE_ROOT:-~/para/project/skills}); this repo must not
    # read those files (#1892). What this repo still owns is the other half of
    # the contract: the helper path and function name the block depends on.
    local fixture="${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/helper_fallback_nf1.sh"
    local helper="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_project_status.sh"
    run grep -F 'if [ -r "$_HELPER" ]; then' "$fixture"
    assert_success
    run grep -F '/functions/gh_project_status.sh"' "$fixture"
    assert_success
    run grep -E '^_gh_project_status_sync\(\) \{' "$helper"
    assert_success
}
