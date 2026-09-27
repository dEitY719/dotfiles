#!/usr/bin/env bats
# tests/bats/scripts/update_skills.bats
# Validate scripts/update-skills.sh (#1825): runs git-pull-skills -> claude/setup.sh
# -> setup-skills-ssot.sh in order, stops on pull failure, --dry-run pulls only.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/update-skills.sh"

# Build a fake dotfiles tree: a copy of the wrapper plus 3 stub steps that
# append their name (and args) to $CALL_LOG. The wrapper resolves its root
# from its own (realpath'd) location, so the copy drives the stubs.
_make_fake_root() {
    local pull_rc="$1"
    FAKE_ROOT="${TEST_TEMP_HOME}/fake-dotfiles"
    CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export CALL_LOG
    mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/claude/plugin" "$FAKE_ROOT/shell-common/tools"
    cp "$SCRIPT_UNDER_TEST" "$FAKE_ROOT/scripts/update-skills.sh"
    ln -s "${DOTFILES_ROOT}/shell-common/tools/ux_lib" "$FAKE_ROOT/shell-common/tools/ux_lib"
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull "$pull_rc"
    _stub "$FAKE_ROOT/claude/setup.sh" claude-setup 0
    _stub "$FAKE_ROOT/scripts/setup-skills-ssot.sh" skills-ssot 0
}

_stub() {
    printf '#!/bin/bash\necho %s "$@" >>"$CALL_LOG"\nexit %s\n' "$2" "$3" >"$1"
    chmod +x "$1"
}

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "update-skills.sh passes bash syntax check" {
    run bash -n "$SCRIPT_UNDER_TEST"
    assert_success
}

@test "update-skills.sh is executable" {
    [ -x "$SCRIPT_UNDER_TEST" ]
}

@test "update-skills.sh runs the 3 steps in order, passing args to pull only" {
    _make_fake_root 0
    cd /
    run "$FAKE_ROOT/scripts/update-skills.sh" --all-branches
    assert_success
    run cat "$CALL_LOG"
    assert_output "pull --all-branches
claude-setup
skills-ssot"
}

@test "update-skills.sh stops before synthesis when git-pull-skills fails" {
    _make_fake_root 1
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    run cat "$CALL_LOG"
    assert_output "pull"
}

@test "update-skills.sh --dry-run runs only the pull dry-run" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_success
    run cat "$CALL_LOG"
    assert_output "pull --dry-run"
}

@test "skills-sync alias points at update-skills.sh" {
    run bash -c "source '${SHELL_COMMON}/aliases/skills_sync.sh' && alias skills-sync"
    assert_success
    assert_output --partial '${HOME}/dotfiles/scripts/update-skills.sh'
}
