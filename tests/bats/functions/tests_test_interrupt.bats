#!/usr/bin/env bats
# tests/bats/functions/tests_test_interrupt.bats
# Issue #2054 — Ctrl+C / SIGTERM must stop the whole run.
#
# run_bats used to block in a foreground `... | xargs -P` pipeline, and bash
# defers a trap until the foreground command returns, so a TERM to tests/test
# left the runner, xargs and every bats worker running (reproduced: 40
# survivors 3s after `kill -TERM`; one such orphan ran for 2+ hours). Workers
# now run in their own process group that the runner `wait`s on, and the
# signal trap kills that group.

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"

setup() {
    setup_isolated_home
    export TMPDIR="$TEST_TEMP_HOME/tmp"
    mkdir -p "$TMPDIR"
    FAKE="$TEST_TEMP_HOME/fake"
    mkdir -p "$FAKE/bats/lib/bats-core/bin" "$FAKE/bats/suite"
    # A per-test sleep length doubles as a pgrep marker for the workers.
    MARK=$((200000 + RANDOM))
    printf '#!/bin/sh\nexec sleep %s\n' "$MARK" >"$FAKE/bats/lib/bats-core/bin/bats"
    chmod +x "$FAKE/bats/lib/bats-core/bin/bats"
    local i
    for i in 1 2 3; do
        printf '@test "x" { :; }\n' >"$FAKE/bats/suite/f$i.bats"
    done
}

teardown() {
    pkill -f "sleep $MARK" 2>/dev/null
    teardown_isolated_home
}

# Start run_bats over the fake suite as a terminal foreground job would run
# (own process group, signals not ignored), registered the way main() does;
# RUN_PID is the runner.
_start_run() {
    set -m
    bash -c "source '$RUNNER'; SCRIPT_DIR='$FAKE'; SERIAL=0; VERBOSE=0
        _register_test_run; _install_test_traps; BATS_JOBS=3 run_bats" >/dev/null 2>&1 </dev/null 3>&- &
    RUN_PID=$!
    set +m
    local i
    for i in $(seq 1 50); do
        [ "$(pgrep -fc "sleep $MARK")" -ge 3 ] && return 0
        sleep 0.2
    done
    false
}

# Every worker and the runner itself are gone within 3s.
_assert_all_gone_within_3s() {
    local i
    for i in $(seq 1 15); do
        if ! pgrep -f "sleep $MARK" >/dev/null && ! kill -0 "$RUN_PID" 2>/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    pgrep -af "sleep $MARK" >&2
    false
}

@test "SIGTERM to the runner stops every bats worker and exits 143" {
    _start_run
    kill -TERM "$RUN_PID"
    _assert_all_gone_within_3s
    local rc=0
    wait "$RUN_PID" || rc=$?
    assert_equal "$rc" 143
}

@test "SIGINT to the runner stops every bats worker and exits 130" {
    _start_run
    kill -INT "$RUN_PID"
    _assert_all_gone_within_3s
    local rc=0
    wait "$RUN_PID" || rc=$?
    assert_equal "$rc" 130
}

@test "an interrupted run removes its registry entry" {
    _start_run
    local entry="$TMPDIR/dotfiles-tests-test-registry-$(id -u)/$RUN_PID"
    [ -e "$entry" ]
    kill -TERM "$RUN_PID"
    _assert_all_gone_within_3s
    [ ! -e "$entry" ]
}
