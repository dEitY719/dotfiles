#!/usr/bin/env bats
# tests/bats/functions/git_worktree_alias_shadow.bats
# Regression test for issue #692 — oh-my-zsh git plugin declares
# `alias gwt='git worktree'`, which shadows dotfiles' gwt() function because
# zsh/bash command parsing resolves aliases before functions.
#
# The fix lives in shell-common/functions/git_worktree.sh (line 9):
#     unalias gwt 2>/dev/null || true
# placed right after the interactive guard and before the function body.
#
# This test pre-declares the conflicting alias before sourcing dotfiles, then
# verifies `type gwt` reports a function — proving the unalias guard removes
# the shadowing alias regardless of plugin load order.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "alias-shadow: pre-existing 'alias gwt=git worktree' removed when dotfiles loads (bash)" {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export TERM=dumb
        shopt -s expand_aliases
        alias gwt='git worktree'
        source '${DOTFILES_ROOT}/bash/main.bash'
        type gwt
    "
    assert_success
    assert_output --partial "is a function"
    refute_output --partial "aliased to"
}

@test "alias-shadow: pre-existing 'alias gwt=git worktree' removed when dotfiles loads (zsh)" {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        alias gwt='git worktree'
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        whence -w gwt
    "
    assert_success
    assert_output --partial "gwt: function"
    refute_output --partial "gwt: alias"
}

@test "alias-shadow: 'gwt help' invokes dotfiles function (not the shadowed git native) in bash" {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export TERM=dumb
        shopt -s expand_aliases
        alias gwt='git worktree'
        source '${DOTFILES_ROOT}/bash/main.bash'
        gwt help
    "
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "alias-shadow: 'gwt help' invokes dotfiles function (not the shadowed git native) in zsh" {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        alias gwt='git worktree'
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        gwt help
    "
    assert_success
    assert_output --partial "Usage: gwt help"
}
