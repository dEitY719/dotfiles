#!/usr/bin/env bats
# tests/bats/functions/tests_test_schedule.bats
# Longest-first scheduling of bats files from recorded durations (#2054).
#
# Ordering by @test count put the real long poles anywhere in the queue; on
# an 8-CPU PC the run ended with a few slow files running alone. Each
# parallel run now records per-file wall time to
# ${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/bats-durations.tsv and the next run
# starts the slowest files first — files with no record (new ones) go first
# of all, and a missing or corrupt cache falls back to the discovery order.

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"

setup() {
    setup_isolated_home
    # shellcheck source=/dev/null
    source "$RUNNER"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME/cache"
    SCRIPT_DIR="$TEST_TEMP_HOME/tests"
    CACHE="$XDG_CACHE_HOME/dotfiles/bats-durations.tsv"
    mkdir -p "${CACHE%/*}"
}

teardown() {
    teardown_isolated_home
}

# Discovery-order input: a b c d (absolute paths under SCRIPT_DIR).
_discovered() {
    printf '%s\n' "$SCRIPT_DIR/bats/a.bats" "$SCRIPT_DIR/bats/b.bats" \
        "$SCRIPT_DIR/bats/c.bats" "$SCRIPT_DIR/bats/d.bats"
}

@test "_bats_durations_file: lives under XDG_CACHE_HOME" {
    assert_equal "$(_bats_durations_file)" "$CACHE"
}

@test "_order_bats_by_duration: slowest recorded first, unrecorded files ahead of all" {
    printf '5\tbats/a.bats\n90\tbats/b.bats\n30\tbats/d.bats\n' >"$CACHE"
    run _order_bats_by_duration < <(_discovered)
    assert_output "$(printf '%s\n' "$SCRIPT_DIR/bats/c.bats" "$SCRIPT_DIR/bats/b.bats" \
        "$SCRIPT_DIR/bats/d.bats" "$SCRIPT_DIR/bats/a.bats")"
}

@test "_order_bats_by_duration: no cache keeps the discovery order" {
    run _order_bats_by_duration < <(_discovered)
    assert_output "$(_discovered)"
}

@test "_order_bats_by_duration: a corrupt cache keeps the discovery order" {
    printf 'garbage\n\x00\x01 not a row\n-3\tbats/b.bats\n' >"$CACHE"
    run _order_bats_by_duration < <(_discovered)
    assert_output "$(_discovered)"
}

@test "_save_bats_durations: records <seconds><TAB><relpath> per file from the run" {
    local out="$TEST_TEMP_HOME/out"
    mkdir -p "$out"
    printf '12' >"$out/0.secs"
    printf '7' >"$out/1.secs"
    _save_bats_durations "$out" "$SCRIPT_DIR/bats/a.bats" "$SCRIPT_DIR/bats/b.bats" "$SCRIPT_DIR/bats/c.bats"
    run cat "$CACHE"
    assert_output "$(printf '12\tbats/a.bats\n7\tbats/b.bats')"
}

@test "_bats_run_file: writes the file's elapsed seconds next to its status" {
    local out="$TEST_TEMP_HOME/out" fake="$TEST_TEMP_HOME/fake-bats"
    mkdir -p "$out"
    printf '#!/bin/sh\nexit 0\n' >"$fake"
    chmod +x "$fake"
    _bats_run_file "$fake" "$out" 4 x.bats
    run cat "$out/4.secs"
    assert_output --regexp '^[0-9]+$'
}
