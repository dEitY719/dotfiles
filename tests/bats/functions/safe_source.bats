#!/usr/bin/env bats
# tests/bats/functions/safe_source.bats
# Regression coverage for issue #1504: safe_source() unconditionally
# redirected a sourced file's stderr to /dev/null, which also swallowed
# WARN output written by a *successfully* sourced file (e.g. #1454's
# foreign-checkout guard) whenever it ran through the interactive loader
# path (bash/main.bash, zsh/main.zsh) instead of being sourced directly.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: a successfully-sourced file's stderr output is no longer swallowed" {
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        declare -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${target}' 'should not error'
        echo \"count=\$SOURCED_FILES_COUNT\"
    "
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "zsh: a successfully-sourced file's stderr output is no longer swallowed" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    local target="$TEST_TEMP_HOME/warns.sh"
    printf '%s\n' 'echo "hello from stderr" >&2' >"$target"

    run zsh -f -c "
        export DOTFILES_FORCE_INIT=1
        typeset -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${target}' 'should not error'
        echo \"count=\$SOURCED_FILES_COUNT\"
    "
    assert_success
    assert_output --partial "hello from stderr"
    assert_output --partial "count=1"
}

@test "bash: a missing file is still silently skipped (no stderr, counter unchanged)" {
    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        declare -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${TEST_TEMP_HOME}/does-not-exist.sh' 'msg'
        echo \"count=\$SOURCED_FILES_COUNT\"
    "
    assert_success
    refute_output --partial "msg"
    assert_output --partial "count=0"
}

@test "bash: a failing */functions/* file reports its error message and its own stderr" {
    local fn_dir="$TEST_TEMP_HOME/functions"
    mkdir -p "$fn_dir"
    local target="$fn_dir/broken.sh"
    printf '%s\n' 'echo "boom detail" >&2; return 1' >"$target"

    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        declare -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${target}' 'load failed'
    "
    assert_failure
    assert_output --partial "load failed"
    assert_output --partial "boom detail"
}

@test "bash: a failing *.local.sh stays fully silent, including its own stderr" {
    local target="$TEST_TEMP_HOME/env.local.sh"
    printf '%s\n' 'echo "should stay hidden" >&2; return 1' >"$target"

    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        declare -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${target}' 'should not print'
    "
    assert_success
    refute_output --partial "should not print"
    refute_output --partial "should stay hidden"
}

# This is the exact scenario issue #1504 reports: a file loaded through the
# real interactive loader path (functions/*, via safe_source) writes a WARN
# to stderr on success and it must now be visible, not just when the same
# file is sourced directly (already covered by
# tests/bats/functions/gh_pr_review.bats's #1454 zsh test).
@test "bash: gh_pr_review.sh's #1454 foreign-checkout WARN survives safe_source" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    local foreign_home="$TEST_TEMP_HOME/foreign-home"
    mkdir -p "$foreign_home/dotfiles"
    git -C "$foreign_home/dotfiles" init -q -b main
    git -C "$foreign_home/dotfiles" -c user.email=t@t -c user.name=t \
        commit --allow-empty -q -m init

    run bash --noprofile --norc -c "
        export HOME='${foreign_home}'
        export DOTFILES_FORCE_INIT=1
        declare -gi SOURCED_FILES_COUNT=0
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/safe_source.sh'
        safe_source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh' 'load failed'
    "
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
}
