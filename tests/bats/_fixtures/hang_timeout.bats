#!/usr/bin/env bats
# tests/bats/_fixtures/hang_timeout.bats
# A test that hangs on purpose, so tests_test_timeout.bats can prove
# BATS_TEST_TIMEOUT converts a #1483-style hang into a bounded TAP failure.
#
# _fixtures/ is excluded from _discover_bats_files() in tests/test, so the real
# suite never runs this — it is only ever invoked directly, with HANG_SLEEP set
# short enough that a broken timeout is caught in seconds rather than minutes.

@test "deliberately hangs forever" {
    sleep "${HANG_SLEEP:-600}"
}
