#!/usr/bin/env bats
# tests/bats/functions/tests_test_timeout.bats
# Unit tests for tests/test's bats per-test timeout containment (#1483).
#
# tests/bats/tools/issue_watcher_cron.bats was observed hanging for hours
# during full-suite runs — a silent stall, not a red test, because nothing in
# the runner bounded a single test's runtime. run_bats() now exports
# BATS_TEST_TIMEOUT (default 300s), so bats-core kills a runaway test and
# reports `# timeout after Ns`, and the summary line says how many tests died
# that way. Root-causing the hang itself is tracked separately (#1483 P1).
#
# tests/test guards its `main "$@"` call with
# `[ "${BASH_SOURCE[0]}" = "${0}" ]`, so this file can source the real script
# and exercise its helpers directly — no test suite is re-entered.

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"
BATS_BIN="${BATS_TEST_DIRNAME}/../lib/bats-core/bin/bats"
HANG_FIXTURE="${BATS_TEST_DIRNAME}/../_fixtures/hang_timeout.bats"
TAP_FIXTURE="${BATS_TEST_DIRNAME}/../_fixtures/timeout_aggregate.tap"

setup() {
    # shellcheck source=/dev/null
    source "$RUNNER"
}

# ---------------------------------------------------------------------------
# End-to-end: a hanging test becomes a bounded failure
#
# (The pure halves of the mechanism — resolving/sanitizing the timeout and
# counting the kills out of a TAP log — have their own unit tests further
# down, against _resolve_bats_timeout() and _count_bats_timeouts(). Neither
# can prove the part that actually matters: that the value we export really
# reaches bats-core and really kills a runaway test. That is this test's job,
# and the only reason it pays the cost of spawning a real bats run.)
# ---------------------------------------------------------------------------

@test "BATS_TEST_TIMEOUT turns a hanging test into a bounded failure" {
    [ -x "$BATS_BIN" ]
    SECONDS=0
    run env BATS_TEST_TIMEOUT=2 HANG_SLEEP=30 "$BATS_BIN" "$HANG_FIXTURE"
    assert_failure
    assert_output --partial "# timeout after 2s"
    # The whole point: killed near the timeout, nowhere near HANG_SLEEP.
    # Bound is generous (not close to the 2s timeout) to tolerate process-
    # spawn overhead on loaded/constrained CI runners (agy review, PR #1492).
    ((SECONDS < 20)) || false
}

# ---------------------------------------------------------------------------
# _discover_bats_files — the hanging fixture must never reach the real suite
# ---------------------------------------------------------------------------

@test "_discover_bats_files: excludes the _fixtures/ directory" {
    run _discover_bats_files
    assert_success
    refute_output --partial "/_fixtures/"
}

@test "_discover_bats_files: still finds real suite files" {
    run _discover_bats_files
    assert_success
    assert_output --partial "/functions/tests_test_timeout.bats"
}

# ---------------------------------------------------------------------------
# _bats_failure_summary — timeouts are reported distinctly from failures
# ---------------------------------------------------------------------------

@test "_bats_failure_summary: omits the timeout clause when nothing timed out" {
    run _bats_failure_summary 1 30 400 0
    assert_success
    assert_output "bats: 1 of 30 files failed (400 tests total)"
}

@test "_bats_failure_summary: reports the timed-out count when there is one" {
    run _bats_failure_summary 2 30 400 3
    assert_success
    assert_output "bats: 2 of 30 files failed (400 tests total, 3 timed out)"
}

# ---------------------------------------------------------------------------
# _resolve_bats_timeout — the sanitize guard run_bats() exports through
#
# Any value that is not a positive integer must land back on 300: bats-core's
# bats_start_timeout_countdown() declares `local -ri timeout=$1`, which errors
# on a bogus value and silently disables the countdown — leaving exactly the
# unbounded hang #1483 exists to prevent (codex review, PR #1492).
# ---------------------------------------------------------------------------

@test "_resolve_bats_timeout: unset BATS_TEST_TIMEOUT defaults to 300" {
    unset BATS_TEST_TIMEOUT
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

@test "_resolve_bats_timeout: an empty BATS_TEST_TIMEOUT falls back to 300" {
    export BATS_TEST_TIMEOUT=""
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

@test "_resolve_bats_timeout: zero falls back to 300" {
    export BATS_TEST_TIMEOUT=0
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

@test "_resolve_bats_timeout: a negative value falls back to 300" {
    export BATS_TEST_TIMEOUT=-1
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

@test "_resolve_bats_timeout: a non-integer string falls back to 300" {
    export BATS_TEST_TIMEOUT=5m
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

@test "_resolve_bats_timeout: a positive integer passes through verbatim" {
    export BATS_TEST_TIMEOUT=45
    run _resolve_bats_timeout
    assert_success
    assert_output "45"
}

# A leading-zero numeral is digit-only, so it survives the [!0-9] filter —
# but bash arithmetic reads a leading zero as octal, which either errors on
# an invalid octal digit or silently changes the value. Both cases must
# resolve to the correct base-10 magnitude, not crash and not silently fall
# back to 300 (agy + codex review, PR #1544).
@test "_resolve_bats_timeout: a leading-zero value is read as decimal, not octal" {
    export BATS_TEST_TIMEOUT=08
    run _resolve_bats_timeout
    assert_success
    assert_output "8"
}

@test "_resolve_bats_timeout: a leading-zero value keeps its decimal magnitude" {
    export BATS_TEST_TIMEOUT=010
    run _resolve_bats_timeout
    assert_success
    assert_output "10"
}

@test "_resolve_bats_timeout: an absurdly long digit string falls back to 300" {
    export BATS_TEST_TIMEOUT=12345678901
    run _resolve_bats_timeout
    assert_success
    assert_output "300"
}

# ---------------------------------------------------------------------------
# _count_bats_timeouts — only real `not ok ... # timeout after Ns` TAP lines
#
# The fixture holds one genuine kill plus the two near-misses the `^not ok`
# anchor exists to reject, so a regression that drops the anchor (or the
# `not ok` requirement) counts 2 or 3 instead of 1 (agy review, PR #1492).
# ---------------------------------------------------------------------------

@test "_count_bats_timeouts: counts only the genuine timeout TAP line" {
    run _count_bats_timeouts "$TAP_FIXTURE"
    assert_success
    assert_output "1"
}

# grep -c prints nothing (not "0") for a missing/unreadable file, and exits
# non-zero whenever the count is 0 — either would break a caller under set -e
# or miscount a clean log as unset (agy + codex review, PR #1544).
@test "_count_bats_timeouts: a missing file still reports 0 with a successful exit" {
    run _count_bats_timeouts "${BATS_TEST_TMPDIR}/does-not-exist.tap"
    assert_success
    assert_output "0"
}

@test "_count_bats_timeouts: a log with zero timeouts still exits successfully" {
    local clean_log="${BATS_TEST_TMPDIR}/no_timeouts.tap"
    printf '1..1\nok 1 something unrelated\n' >"$clean_log"
    run _count_bats_timeouts "$clean_log"
    assert_success
    assert_output "0"
}
