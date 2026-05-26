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
#
# Note on `eval 'gwt help'` in the dispatch tests below: in `bash -c` / `zsh -c`
# the whole script string is parsed before any runtime `alias` command takes
# effect, so a plain `gwt help` is never alias-expanded — the test would pass
# even with a broken unalias guard (false positive, PR #693 review). `eval`
# forces a runtime re-parse at the point where the alias *is* registered, so
# only a working guard prevents the alias from expanding to `git worktree`.
#
# Post-#746: `gwt help` (legacy 공백 형식) 은 dotfiles 함수가 명시적으로
# 거부 (`exit 1` + canonical-entrypoint 안내). 함수 호출이 실제로 일어났는지
# (alias shadow 가 무효화됐는지) 검증할 때, 거부 메시지 그 자체가 dotfiles
# 함수만이 생성하는 고유 시그니처이므로 git native (`git worktree help` →
# git 자체 도움말) 와 명확히 구분된다.

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
        eval 'gwt help' 2>&1
    "
    # Post-#746: dotfiles 함수는 'gwt help' 를 거부 (exit 1) + canonical
    # entrypoint 안내. git native ('git worktree help') 가 호출됐다면
    # 이 시그니처가 절대 나오지 않으므로 alias-shadow 가 무효화됐음을 증명.
    assert_failure
    assert_output --partial "canonical entrypoint: gwt-help"
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
        eval 'gwt help' 2>&1
    "
    assert_failure
    assert_output --partial "canonical entrypoint: gwt-help"
}
