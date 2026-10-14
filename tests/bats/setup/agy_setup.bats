#!/usr/bin/env bats
# tests/bats/setup/agy_setup.bats
# Issue #2142 — agy/setup.sh idempotency via run_module_setup (2 runs, 2nd
# run touches nothing under $HOME). `agy` is stubbed on PATH.

load '../test_helper'

teardown() {
    teardown_isolated_home
}

setup() {
    setup_isolated_home
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    export PATH="${STUB_BIN}:/usr/bin:/bin"
}

@test "agy: idempotent without the CLI, prints install guidance" {
    run_module_setup agy
    assert_output --partial "antigravity.google/cli/install.sh"
}

@test "agy: idempotent with the CLI stubbed" {
    printf "#!/bin/sh\nexit 0\n" >"$STUB_BIN/agy"
    chmod +x "$STUB_BIN/agy"
    run_module_setup agy
    assert_output --partial "$STUB_BIN/agy"
}
