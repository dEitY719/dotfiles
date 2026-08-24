#!/usr/bin/env bats
# tests/bats/functions/tests_test_throttle.bats
# Unit tests for tests/test's concurrency self-throttling helpers (#1413).
#
# On a multi-worktree machine every `./tests/test` invocation used to claim
# all $(nproc) cores for itself (bats via `xargs -P`, pytest via `-n auto`),
# so three or four simultaneous runs oversubscribed the host and each got a
# fraction of a core. The runner now registers itself in a TMPDIR-scoped
# registry, counts the *other* live runs, and divides the job pool among
# them.
#
# tests/test guards its `main "$@"` call with
# `[ "${BASH_SOURCE[0]}" = "${0}" ]`, so this file can source the real script
# and exercise its helpers directly — no test suite is re-entered.
#
# Registry entries are keyed by PID and liveness is re-checked with `kill -0`
# at read time, so these tests fabricate peers by writing PID-named files
# (dead PID = ignored, live PID = counted) instead of spawning real runners.

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"

# A PID far above any Linux/macOS pid_max, so it is guaranteed not running.
DEAD_PID=999999999

setup() {
    setup_isolated_home
    # _test_run_registry_dir() is TMPDIR-derived; a per-test TMPDIR keeps
    # these assertions independent of any real ./tests/test running on this
    # machine (and of each other).
    export TMPDIR="$TEST_TEMP_HOME/tmp"
    mkdir -p "$TMPDIR"
    # shellcheck source=/dev/null
    source "$RUNNER"
    REGISTRY="$(_test_run_registry_dir)"
    PEER_PIDS=()
}

teardown() {
    local pid
    for pid in ${PEER_PIDS[@]+"${PEER_PIDS[@]}"}; do
        kill "$pid" 2>/dev/null
    done
    teardown_isolated_home
}

# Register N fabricated peers whose PIDs belong to genuinely running
# processes. stdio is redirected and fd 3 closed so a background job can
# never hold bats' output pipes open.
register_live_peers() {
    local n="$1" i pid
    mkdir -p "$REGISTRY"
    for ((i = 0; i < n; i++)); do
        sleep 30 >/dev/null 2>&1 3>&- &
        pid=$!
        PEER_PIDS+=("$pid")
        : >"$REGISTRY/$pid"
    done
}

# ---------------------------------------------------------------------------
# _test_run_registry_dir
# ---------------------------------------------------------------------------

@test "_test_run_registry_dir: returns a non-empty path under TMPDIR" {
    run _test_run_registry_dir
    assert_success
    [ -n "$output" ]
    assert_output --partial "$TMPDIR/"
}

# ---------------------------------------------------------------------------
# _concurrent_test_run_count
# ---------------------------------------------------------------------------

@test "_concurrent_test_run_count: 0 when the registry dir does not exist" {
    [ ! -d "$REGISTRY" ]
    run _concurrent_test_run_count
    assert_success
    assert_output "0"
}

@test "_concurrent_test_run_count: 0 when the registry dir is empty" {
    mkdir -p "$REGISTRY"
    run _concurrent_test_run_count
    assert_success
    assert_output "0"
}

@test "_concurrent_test_run_count: ignores an entry whose PID is not running" {
    mkdir -p "$REGISTRY"
    : >"$REGISTRY/$DEAD_PID"
    run _concurrent_test_run_count
    assert_success
    assert_output "0"
}

@test "_concurrent_test_run_count: counts a live peer and excludes this PID" {
    register_live_peers 1
    : >"$REGISTRY/$$"
    run _concurrent_test_run_count
    assert_success
    assert_output "1"
}

@test "_concurrent_test_run_count: counts only the live peers among stale entries" {
    register_live_peers 2
    : >"$REGISTRY/$DEAD_PID"
    run _concurrent_test_run_count
    assert_success
    assert_output "2"
}

# ---------------------------------------------------------------------------
# _register_test_run
# ---------------------------------------------------------------------------

@test "_register_test_run: creates this PID's entry without self-counting" {
    run _register_test_run
    assert_success
    [ -f "$REGISTRY/$$" ]
    run _concurrent_test_run_count
    assert_output "0"
}

@test "_register_test_run: no-ops when the registry dir cannot be created" {
    export TMPDIR="/dev/null/not-a-dir"
    run _register_test_run
    assert_success
    run _concurrent_test_run_count
    assert_success
    assert_output "0"
}

# ---------------------------------------------------------------------------
# _effective_parallel_jobs
# ---------------------------------------------------------------------------

@test "_effective_parallel_jobs: returns the base unchanged with no peers" {
    run _effective_parallel_jobs 20
    assert_success
    assert_output "20"
}

@test "_effective_parallel_jobs: halves the base with one peer" {
    register_live_peers 1
    run _effective_parallel_jobs 20
    assert_success
    assert_output "10"
}

@test "_effective_parallel_jobs: divides by peers+1 with three peers" {
    register_live_peers 3
    run _effective_parallel_jobs 20
    assert_success
    assert_output "5"
}

@test "_effective_parallel_jobs: floors at 1, never 0" {
    register_live_peers 3
    run _effective_parallel_jobs 1
    assert_success
    assert_output "1"
}

@test "_effective_parallel_jobs: passes a non-numeric base through unchanged" {
    register_live_peers 1
    run _effective_parallel_jobs "abc"
    assert_success
    assert_output "abc"
}

@test "_effective_parallel_jobs: passes an empty base through unchanged" {
    run _effective_parallel_jobs ""
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# _resolve_bats_jobs — the run_bats() job-count decision
# ---------------------------------------------------------------------------

@test "_resolve_bats_jobs: an explicit BATS_JOBS wins over throttling" {
    register_live_peers 3
    export BATS_JOBS=7
    run _resolve_bats_jobs
    assert_success
    assert_output "7"
}

@test "_resolve_bats_jobs: a non-numeric BATS_JOBS falls back to 4" {
    export BATS_JOBS=abc
    run _resolve_bats_jobs
    assert_success
    assert_output "4"
}

@test "_resolve_bats_jobs: throttles the CPU default when BATS_JOBS is unset" {
    unset BATS_JOBS
    local base expected
    base="$(_resolve_bats_jobs)"
    register_live_peers 1
    expected=$((base / 2))
    [ "$expected" -lt 1 ] && expected=1
    run _resolve_bats_jobs
    assert_success
    assert_output "$expected"
}
