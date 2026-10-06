#!/usr/bin/env bats
# tests/bats/functions/tests_test_progress.bats
# Unit tests for tests/test's bats progress ticker (#2043).

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"

setup() {
    setup_isolated_home
    # shellcheck source=/dev/null
    source "$RUNNER"
    OUTDIR="$TEST_TEMP_HOME/out"
    mkdir -p "$OUTDIR"
}

# Run the ticker for ~1.5 ticks (1s interval) in a non-TTY subshell.
_tick_once() {
    BATS_PROGRESS_INTERVAL=1 _bats_progress_ticker "$OUTDIR" 5 &
    local pid=$!
    sleep 1.5
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

@test "ticker prints finished/total count from *.status files" {
    printf 0 >"$OUTDIR/0.status"
    printf 0 >"$OUTDIR/1.status"
    run _tick_once
    [[ "$output" == *"[2/5 files]"* ]]
}

@test "non-TTY output is plain lines with no carriage return" {
    run _tick_once
    [[ "$output" != *$'\r'* ]]
    [[ "$output" == *"[0/5 files]"* ]]
}
