#!/usr/bin/env bats
# tests/bats/tools/check_help_flag.bats
# check_* diagnostics: -h/--help print usage, exit 0 and run no check (#1912).
# Before: most exited 1 as an unknown subcommand, check_pip ran the full check,
# check_proxy logged "Unknown mode" and record_fail.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_DIR="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_DIR"
    : >"$CALL_LOG"
    # Every external tool a check would touch logs its call instead of running.
    local tool
    for tool in apt apt-get apt-cache apt-config cargo npm node dotnet nuget \
        pip pip3 python python3 uv rpm yum dnf curl wget ssh-keygen git; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$tool" "$CALL_LOG" >"$STUB_DIR/$tool"
        chmod +x "$STUB_DIR/$tool"
    done
}

teardown() {
    teardown_isolated_home
}

@test "check_* -h|--help: usage, exit 0, no external tool called, no check output" {
    local name flag
    for name in check_apt check_cargo check_npm check_nuget check_pip \
        check_proxy check_rpm check_ssh check_uv; do
        for flag in -h --help; do
            # Real ux_lib (init.sh returns before loading it under test mode).
            run env -u DOTFILES_TEST_MODE PATH="$STUB_DIR:$PATH" HOME="$HOME" \
                TERM=dumb bash "${SHELL_COMMON}/tools/custom/${name}.sh" "$flag"
            assert_success
            assert_output --partial "Usage"
            assert_output --partial "$name"
            refute_output --partial "Unknown mode"
            refute_output --partial "Summary"
        done
    done
    run cat "$CALL_LOG"
    assert_output ""
}

@test "check_* unknown subcommand still prints usage and exits 1" {
    local name
    for name in check_apt check_cargo check_npm check_nuget check_rpm check_ssh check_uv; do
        run env -u DOTFILES_TEST_MODE PATH="$STUB_DIR:$PATH" HOME="$HOME" \
            TERM=dumb bash "${SHELL_COMMON}/tools/custom/${name}.sh" bogus
        assert_failure 1
        assert_output --partial "Usage"
    done
}
