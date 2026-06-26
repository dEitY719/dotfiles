#!/usr/bin/env bats
# tests/bats/tools/obsidian.bats
# Black-box tests for the standalone `obsidian` executable (issue #1023).
# It is a PATH executable (not a shell function), so we invoke the script
# directly with env overrides and assert on output / exit code.
#
# Note: the WSL branch is exercised by forcing WSL_DISTRO_NAME. The native
# Linux (AppImage) branch is not unit-tested here because the test host is
# itself WSL (/proc/version contains "microsoft"), so it cannot be forced
# off without a production test-hook — out of scope.

load '../test_helper'

OBSIDIAN_BIN="${DOTFILES_ROOT}/obsidian/bin/obsidian"

@test "obsidian executable exists and is executable" {
    [ -x "$OBSIDIAN_BIN" ]
}

@test "obsidian passes shellcheck" {
    run shellcheck "$OBSIDIAN_BIN"
    assert_success
}

@test "obsidian -h shows wrapper help (exit 0)" {
    run "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "obsidian - launch Obsidian"
    assert_output --partial "Usage"
}

@test "obsidian --help shows help" {
    run "$OBSIDIAN_BIN" --help
    assert_success
    assert_output --partial "Usage"
}

@test "obsidian help (bare word) shows help" {
    run "$OBSIDIAN_BIN" help
    assert_success
    assert_output --partial "Usage"
}

@test "WSL: missing redirector returns 127 with guidance + path" {
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN=/no/such/Obsidian.com \
        "$OBSIDIAN_BIN" search query=x
    assert_failure 127
    assert_output --partial "CLI redirector not found"
    assert_output --partial "/no/such/Obsidian.com"
}

@test "WSL: existing-but-non-executable redirector passes the -f gate (not 127)" {
    # DrvFs files can lack +x yet run via interop, so the launcher tests -f not -x.
    local stub="${BATS_TEST_TMPDIR}/Obsidian.com"
    printf '#!/bin/sh\necho RAN "$@"\n' > "$stub"
    chmod 0644 "$stub" # deliberately NOT executable
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN="$stub" "$OBSIDIAN_BIN" read file=x
    [ "$status" -ne 127 ]
    refute_output --partial "CLI redirector not found"
}

@test "bash runs the POSIX script (help)" {
    run bash "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "Usage"
}

@test "zsh runs the POSIX script (help)" {
    run zsh "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "Usage"
}
