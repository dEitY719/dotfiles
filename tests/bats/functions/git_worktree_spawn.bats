#!/usr/bin/env bats
# tests/bats/functions/git_worktree_spawn.bats
# Tests for `gwt spawn --agent` flag (issue #162).
# Focuses on argument parsing + validation paths that do NOT require tmux
# or a real worktree layout — the interesting behavioral change is the
# decoupling of worktree <name> from the tmux agent name.

load '../test_helper'

_setup_fake_main_repo() {
    FAKE_REPO="$TEST_TEMP_HOME/fake-main"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    git init -q --initial-branch=main "$FAKE_REPO"
    (
        cd "$FAKE_REPO"
        echo base >base.txt
        git add base.txt
        git commit -q -m base
    )
}

setup() {
    setup_isolated_home
    _setup_fake_main_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
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

@test "bash: spawn --help mentions --launch flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--launch"
}

@test "bash: spawn rejects --tmux and --launch together" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --launch 2>&1
    "
    assert_failure
    assert_output --partial "mutually exclusive"
}

@test "bash: spawn rejects unknown agent when --launch is used" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --agent notarealagent 2>&1
    "
    assert_failure
    assert_output --partial "Unknown agent: notarealagent"
}

@test "zsh: spawn --help mentions --launch flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--launch"
}

@test "bash: spawn auto-increments when branch exists without worktree" {
    run_in_bash "
        cd '$FAKE_REPO' || exit 1
        git branch wt/feat/1
        git_worktree_spawn feat 2>&1
        git show-ref --verify --quiet refs/heads/wt/feat/2 && echo BRANCH2_OK
        [ -d '$TEST_TEMP_HOME/fake-main-feat-2' ] && echo PATH2_OK
    "
    assert_success
    assert_output --partial "Branch: wt/feat/2"
    assert_output --partial "BRANCH2_OK"
    assert_output --partial "PATH2_OK"
}
