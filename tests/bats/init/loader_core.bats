#!/usr/bin/env bats
# tests/bats/init/loader_core.bats
# Loading core shared by bash/main.bash and zsh/main.zsh (#2134):
# util/bootstrap.sh prelude + safe_source-based load_category.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# (a) load_category goes through safe_source, so a broken functions file's
# stderr and the failure report stay visible (#1454/#1504) instead of being
# swallowed by `2>/dev/null`.
@test "bash: load_category surfaces a broken functions file" {
    fixture="$TEST_TEMP_HOME/fixture"
    mkdir -p "$fixture/functions"
    printf 'echo broken-fixture-stderr >&2\nfalse\n' >"$fixture/functions/broken.sh"
    run bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        SOURCED_FILES_COUNT=0
        . '${SHELL_COMMON}/util/safe_source.sh'
        . '${SHELL_COMMON}/util/loader.sh'
        load_category functions '$fixture'
        echo COUNT=\$SOURCED_FILES_COUNT
    " 2>&1
    assert_success
    assert_output --partial "broken-fixture-stderr"
    assert_output --partial "Failed to load functions: $fixture/functions/broken.sh"
    assert_output --partial "COUNT=0"
}

# (b) every counted file has exactly one DEBUG "Loaded:" line.
_assert_count_matches_loaded() {
    local loaded count
    loaded=$(printf '%s\n' "$output" | grep -c 'DEBUG: Loaded: ')
    count=$(printf '%s\n' "$output" | sed -n 's/^COUNT=//p')
    [ "$loaded" -gt 0 ]
    [ "$count" = "$loaded" ] || fail "SOURCED_FILES_COUNT=$count, Loaded lines=$loaded"
}

@test "bash: SOURCED_FILES_COUNT equals DEBUG Loaded line count" {
    export DEBUG_DOTFILES=1
    run_in_bash 'echo "COUNT=$SOURCED_FILES_COUNT"'
    _assert_count_matches_loaded
}

@test "zsh: SOURCED_FILES_COUNT equals DEBUG Loaded line count" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    export DEBUG_DOTFILES=1
    run_in_zsh 'echo "COUNT=$SOURCED_FILES_COUNT"'
    _assert_count_matches_loaded
}

# (c) the Codex guard applies to zsh too, not only bash.
_zsh_codex() {
    run env -u DOTFILES_FORCE_INIT DOTFILES_ROOT_NO_CANONICALIZE=1 TERM=dumb "$@" \
        zsh -f -i -c "DOTFILES_ROOT='$DOTFILES_ROOT'; . '$DOTFILES_ROOT/zsh/main.zsh'; typeset -f gwt"
}

@test "zsh: CODEX_CLI=1 skips initialization" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    _zsh_codex CODEX_CLI=1
    refute_output --partial "gwt"
}

@test "zsh: without Codex env the same shell defines gwt" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    _zsh_codex
    assert_output --partial "gwt"
}

@test "bash: CODEX_CLI=1 skips initialization" {
    run env -u DOTFILES_FORCE_INIT DOTFILES_ROOT_NO_CANONICALIZE=1 TERM=dumb CODEX_CLI=1 \
        bash --noprofile --norc -i -c ". '$DOTFILES_ROOT/bash/main.bash'; declare -F gwt"
    refute_output --partial "gwt"
}

@test "zsh: DOTFILES_SKIP_INIT=1 skips initialization" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    _zsh_codex DOTFILES_SKIP_INIT=1
    refute_output --partial "gwt"
}

# *help cleanup now runs in zsh too: a stale help function is dropped, while
# my_help and zsh's own run-help survive.
@test "zsh: dotfiles_load_all clears stale *help functions but keeps run-help" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run_in_zsh '
        stale_fixture_help() { :; }
        function run-help { :; }
        function my_help { :; }
        dotfiles_load_all
        typeset +f stale_fixture_help >/dev/null 2>&1 && echo stale-kept
        typeset +f run-help >/dev/null 2>&1 && echo run-help-kept
        typeset +f my_help >/dev/null 2>&1 && echo my-help-kept
    '
    refute_output --partial "stale-kept"
    assert_output --partial "run-help-kept"
    assert_output --partial "my-help-kept"
}

@test "zsh: load_category on an empty category is a quiet no-op" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    mkdir -p "$TEST_TEMP_HOME/empty/functions"
    run_in_zsh "load_category functions '$TEST_TEMP_HOME/empty' && echo rc0"
    assert_success
    refute_output --partial "no matches found"
    assert_output --partial "rc0"
}

# #2181: the direct-exec guard judges by ${0##*/} alone (no BASH_SOURCE), and
# must not fire when zsh rebinds $0 to the sourced file.
@test "loader.sh refuses direct execution but sources under bash and zsh" {
    loader="${_BATS_REAL_DOTFILES_ROOT}/shell-common/util/loader.sh"
    run env DOTFILES_FORCE_INIT=1 bash "$loader"
    assert_failure
    assert_output --partial 'should be sourced, not executed'
    run env DOTFILES_FORCE_INIT=1 zsh --no-rcs "$loader"
    assert_failure
    assert_output --partial 'should be sourced, not executed'
    run env DOTFILES_FORCE_INIT=1 bash -c ". '$loader' && command -v load_category"
    assert_success
    run env DOTFILES_FORCE_INIT=1 zsh --no-rcs -c ". '$loader' && whence load_category"
    assert_success
}
