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

setup() {
    # shellcheck source=/dev/null
    source "$RUNNER"
}

# ---------------------------------------------------------------------------
# End-to-end: a hanging test becomes a bounded failure
#
# (run_bats() resolves the timeout inline as `${BATS_TEST_TIMEOUT:-300}` — a
# bare bash default expansion, not a helper worth unit-testing on its own.
# This test exercises the real behavior: an explicit override reaching
# bats-core and killing a runaway test.)
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
