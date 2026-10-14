#!/usr/bin/env bats
# tests/bats/functions/skill_under_workspace.bats
# Cover _skill_under_workspace (shell-common/functions/skill_sources.sh), the
# one "does this link point into the workspace?" rule shared by
# scripts/setup-skills-ssot.sh (skill_source_is_managed) and the Claude Code
# account skills lib (prune / link --list / link fan-out skip) — issue #2147.

load '../test_helper'

setup() {
    setup_isolated_home
    WS="$TEST_TEMP_HOME/workspace"
    mkdir -p "$WS/repo/skills/one"
    ln -s "$WS" "$TEST_TEMP_HOME/ws-link"
    # shellcheck source=/dev/null
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
}

teardown() {
    teardown_isolated_home
}

@test "path under the default root (WORKSPACE_ROOT) is inside" {
    WORKSPACE_ROOT="$WS" run _skill_under_workspace "$WS/repo/skills/one"
    assert_success
}

@test "path under the resolved spelling of a symlinked root is inside" {
    WORKSPACE_ROOT="$TEST_TEMP_HOME/ws-link" run _skill_under_workspace "$WS/repo/skills/one"
    assert_success
}

@test "path outside the root, the root itself and an empty path are outside" {
    WORKSPACE_ROOT="$WS" run _skill_under_workspace "$TEST_TEMP_HOME/other/one"
    assert_failure
    WORKSPACE_ROOT="$WS" run _skill_under_workspace "$WS"
    assert_failure
    WORKSPACE_ROOT="$WS" run _skill_under_workspace ""
    assert_failure
}

@test "no usable root (missing or too broad) means nothing is inside" {
    WORKSPACE_ROOT="$TEST_TEMP_HOME/missing" run _skill_under_workspace "$TEST_TEMP_HOME/missing/x"
    assert_failure
    WORKSPACE_ROOT="$HOME" run _skill_under_workspace "$HOME/x"
    assert_failure
}

@test "explicit root and real-root arguments skip the lookup" {
    WORKSPACE_ROOT="$TEST_TEMP_HOME/missing" run _skill_under_workspace "$WS/a" "$WS"
    assert_success
    run _skill_under_workspace "/real/a" "/raw" "/real"
    assert_success
    run _skill_under_workspace "/elsewhere/a" "/raw" "/real"
    assert_failure
}

@test "the rule has one definition: no per-consumer copy remains" {
    run grep -rn '_claude_under_workspace' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common" "${_BATS_REAL_DOTFILES_ROOT}/scripts"
    assert_failure
    run grep -c '_skill_under_workspace' "${_BATS_REAL_DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"
    assert_success
}
