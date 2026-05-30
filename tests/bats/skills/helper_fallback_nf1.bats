#!/usr/bin/env bats
# tests/bats/skills/helper_fallback_nf1.bats
# Smoke test for issue #644 — helper-fallback NF-1.
#
# Verifies the canonical `[ -r ]` guard + `|| true` block applied to all
# helper source points across:
#   gh-pr-merge / gh-pr / gh-pr-reply / gh-pr-merge-emergency / gh-commit
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

@test "fixture mirrors the SKILL.md canonical pattern verbatim (drift guard)" {
    # If this test fails, the F-2 canonical pattern in one of the SKILL.md
    # files has drifted from the fixture in
    # tests/bats/skills/_fixtures/helper_fallback_nf1.sh.  Re-sync both.
    local fixture="${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/helper_fallback_nf1.sh"
    run grep -F 'if [ -r "$_HELPER" ]; then' "$fixture"
    assert_success

    # Spot-check that each skill's canonical helper-fallback guard carries
    # through. NOTE: #862 PR-NW-4 relocated these bash blocks out of the
    # SKILL.md bodies into references/ for progressive disclosure (Check 1
    # line-count ≤100). Each owning SKILL.md Step now points at the reference
    # and the model pastes it verbatim, so the guard still executes — the
    # drift check just follows it to its new home. (This reverses the #747
    # inlining for gh-pr.)
    local f
    for f in \
        "claude/skills/gh-pr-merge/references/board-approval-gate.sh.md" \
        "claude/skills/gh-pr-merge/references/project-board-sync.md" \
        "claude/skills/gh-commit/SKILL.md" \
        "claude/skills/gh-pr-reply/references/board-sync-in-review.sh.md" \
        "claude/skills/gh-pr/references/project-board-sync.md" \
        "claude/skills/gh-pr-merge-emergency/references/project-board-sync.md"; do
        run grep -F 'if [ -r "$_HELPER" ]; then' "${_BATS_REAL_DOTFILES_ROOT}/$f"
        assert_success
    done
}
