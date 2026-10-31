#!/usr/bin/env bats
# tests/bats/integrations/pipefail_dependents.bats
# These commands relied on the global pipefail removed in #2332 to reach their
# failure paths, so each one now tests the failing stage directly. Every CLI is
# a stub on PATH.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    teardown_isolated_home
}

_stub() {
    printf '#!/bin/sh\n%s\n' "$2" >"$STUB_BIN/$1"
    chmod +x "$STUB_BIN/$1"
}

# Aliases do not expand in `bash -c`, so run the alias body directly.
_run_pp_freeze() {
    cd "$HOME"
    run_in_bash "cd '$HOME'; eval \"\${BASH_ALIASES[pp_freeze]}\""
}

@test "dcl: docker ps failure warns instead of printing an empty section" {
    _stub docker 'exit 1'
    run_in_bash 'dcl'
    assert_success
    assert_output --partial 'No running containers found'
}

@test "dcl: running containers are listed without the warning" {
    _stub docker 'printf "NAMES\nweb\n"'
    run_in_bash 'dcl'
    assert_success
    assert_output --partial 'web'
    refute_output --partial 'No running containers found'
}

@test "npm_list: failed npm list prints the fallback" {
    _stub npm 'exit 1'
    run_in_bash 'npm_list'
    assert_output --partial 'No global npm packages'
}

@test "mount_show: an unmounted path reports it and returns 1" {
    _stub findmnt 'exit 1'
    run_in_bash 'mount_show /nope'
    assert_failure
    assert_output --partial 'Not mounted: /nope'
}

@test "pp_freeze: a pyproject without a name leaves requirements.txt alone" {
    _stub pip 'echo keep==1'
    printf '[project]\n' >"$HOME/pyproject.toml"
    printf 'old==1\n' >"$HOME/requirements.txt"
    _run_pp_freeze
    assert_failure
    run cat "$HOME/requirements.txt"
    assert_output 'old==1'
}

@test "pp_freeze: a failed pip freeze leaves requirements.txt alone" {
    _stub pip 'exit 1'
    printf '[project]\nname = "demo"\n' >"$HOME/pyproject.toml"
    printf 'old==1\n' >"$HOME/requirements.txt"
    _run_pp_freeze
    assert_failure
    run cat "$HOME/requirements.txt"
    assert_output 'old==1'
}

@test "pp_freeze: only the first top-level name filters the freeze output" {
    _stub pip 'printf "demo==1\nkeep==1\n"'
    printf '[project]\nname = "demo"\n[[tool.uv.index]]\nname = ""\n[[tool.uv.index]]\nname = "other"\n' >"$HOME/pyproject.toml"
    _run_pp_freeze
    assert_success
    run cat "$HOME/requirements.txt"
    assert_output "$(printf 'keep==1\n-e .')"
}
