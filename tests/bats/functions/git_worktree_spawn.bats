#!/usr/bin/env bats
# tests/bats/functions/git_worktree_spawn.bats
# Tests for `gwt spawn --agent` flag (issue #162).
# Focuses on argument parsing + validation paths that do NOT require tmux
# or a real worktree layout — the interesting behavioral change is the
# decoupling of worktree <name> from the tmux agent name.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: git_worktree_spawn function exists" {
    run_in_bash 'declare -f git_worktree_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: spawn --help mentions --agent flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--agent"
    assert_output --partial "claude"
}

@test "bash: spawn --help no longer shows the <name>-yolo caveat" {
    # The old caveat read "The pane runs '<name>-yolo'". After the agent
    # decoupling, tmux windows run '<agent>-yolo' regardless of <name>.
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    refute_output --partial "<name>-yolo"
}

@test "bash: spawn rejects unknown agent when --tmux is used" {
    # --tmux triggers the agent validation path. Use a name inside an
    # isolated dir so we reach validation without spawning anything real.
    # The key assertion: an unknown agent must produce a helpful error.
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --agent notarealagent 2>&1
    "
    assert_failure
    assert_output --partial "Unknown agent: notarealagent"
    assert_output --partial "claude"
}

@test "zsh: git_worktree_spawn function exists" {
    run_in_zsh 'declare -f git_worktree_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: spawn --help mentions --agent flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--agent"
}
