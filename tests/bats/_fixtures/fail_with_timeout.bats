#!/usr/bin/env bats
# tests/bats/_fixtures/fail_with_timeout.bats
# One ordinary failing test, loaded through the real test_helper, so
# tests_test_timeout.bats can prove a red test no longer stalls its whole file
# for BATS_TEST_TIMEOUT (#2054). Excluded from discovery like every _fixtures/
# file; only ever invoked directly.

load '../test_helper'

@test "deliberately fails" {
    [ 1 -eq 2 ]
}

@test "passes after the failure" {
    :
}
