#!/usr/bin/env bash
# tests/bats/test_helper.bash
# Common helper for all bats tests.
# Provides environment isolation and dotfiles loading via subprocesses.

# Load bats libraries
_BATS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
load "${_BATS_LIB_DIR}/bats-support/load"
load "${_BATS_LIB_DIR}/bats-assert/load"

# Project paths
export DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Test isolation
export DOTFILES_TEST_MODE=1
export DOTFILES_FORCE_INIT=1

setup_isolated_home() {
    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    export ZDOTDIR="$TEST_TEMP_HOME"
    export XDG_CONFIG_HOME="$TEST_TEMP_HOME"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME"
    export XDG_DATA_HOME="$TEST_TEMP_HOME"
    export TERM=dumb
}

teardown_isolated_home() {
    if [ -n "$TEST_TEMP_HOME" ] && [ -d "$TEST_TEMP_HOME" ]; then
        rm -rf "$TEST_TEMP_HOME"
    fi
}

# Run a command in bash subprocess with dotfiles loaded
run_in_bash() {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash'
        $1
    "
}

# Run a command in zsh subprocess with dotfiles loaded
run_in_zsh() {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        $1
    "
}
