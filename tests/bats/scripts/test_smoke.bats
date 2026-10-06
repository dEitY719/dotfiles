#!/usr/bin/env bats
# tests/bats/scripts/test_smoke.bats
#
# Issue #2046 — scripts/test_smoke.sh (`mise run test-smoke`), the pre-push
# Layer 0 smoke: syntax check of changed shell files, only the bats files
# mapped from the changed paths, `pytest -m smoke`, all under a time budget.
#
# Each test builds a throwaway git repo (cwd) with a fake tests/bats tree.
# SMOKE_BATS / SMOKE_PYTEST point at stubs that log their argv, so the
# assertions are about *which* files the script selects, not real bats runs.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/scripts/test_smoke.sh"

setup() {
    setup_isolated_home
    REPO="${TEST_TEMP_HOME}/repo"
    CALLS="${TEST_TEMP_HOME}/calls.log"
    mkdir -p "$REPO/tests/bats/functions" "$REPO/tests/bats/git" "$REPO/tests/bats/lib" \
        "$REPO/shell-common/functions" "$REPO/docs"
    cd "$REPO" || return 1
    git init -q .
    git config user.email t@t && git config user.name t
    : >tests/bats/functions/gcp.bats
    : >tests/bats/functions/git_restore.bats
    : >tests/bats/git/test_pre_push_pytest.bats
    : >tests/bats/lib/gcp.bats # vendored bats-core: never selected
    printf 'f() { :; }\n' >shell-common/functions/gcp_scan.sh
    printf 'x\n' >docs/notes.txt
    git add -A && git commit -qm base
    BASE=$(git rev-parse HEAD)

    printf '#!/bin/sh\necho "bats $*" >>"%s"\nexit "${STUB_BATS_RC:-0}"\n' "$CALLS" >"${TEST_TEMP_HOME}/bats"
    printf '#!/bin/sh\necho "pytest $*" >>"%s"\n' "$CALLS" >"${TEST_TEMP_HOME}/pytest"
    chmod +x "${TEST_TEMP_HOME}/bats" "${TEST_TEMP_HOME}/pytest"
    export SMOKE_BATS="${TEST_TEMP_HOME}/bats" SMOKE_PYTEST="${TEST_TEMP_HOME}/pytest"
}

teardown() {
    teardown_isolated_home
}

_commit() {
    printf '%s\n' "$2" >>"$1"
    git add -A && git commit -qm change
}

@test "test_smoke: gcp_scan.sh change selects gcp.bats only (regression #2046)" {
    _commit shell-common/functions/gcp_scan.sh 'g() { :; }'

    run sh "$SCRIPT" "${BASE}..HEAD"

    assert_success
    run cat "$CALLS"
    assert_line "bats tests/bats/functions/gcp.bats"
    refute_output --partial "git_restore.bats"
    refute_output --partial "tests/bats/lib/"
    assert_line --partial "pytest"
}

@test "test_smoke: hook name maps dash to underscore (pre-push -> test_pre_push_*.bats)" {
    mkdir -p git/hooks
    _commit git/hooks/pre-push 'exit 0'

    run sh "$SCRIPT" "${BASE}..HEAD"

    assert_success
    run cat "$CALLS"
    assert_line "bats tests/bats/git/test_pre_push_pytest.bats"
}

@test "test_smoke: unmapped change runs no bats" {
    _commit docs/notes.txt 'more'

    run sh "$SCRIPT" "${BASE}..HEAD"

    assert_success
    run cat "$CALLS"
    refute_output --partial "bats "
}

@test "test_smoke: range read from PRE_PUSH_SMOKE_RANGES when no args" {
    _commit shell-common/functions/gcp_scan.sh 'g() { :; }'

    PRE_PUSH_SMOKE_RANGES="${BASE}..HEAD" run sh "$SCRIPT"

    assert_success
    run cat "$CALLS"
    assert_line "bats tests/bats/functions/gcp.bats"
}

@test "test_smoke: syntax error in changed .sh fails" {
    _commit shell-common/functions/gcp_scan.sh 'if then fi ('

    run sh "$SCRIPT" "${BASE}..HEAD"

    assert_failure
    assert_output --partial "gcp_scan.sh"
}

@test "test_smoke: failing mapped bats fails" {
    _commit shell-common/functions/gcp_scan.sh 'g() { :; }'

    STUB_BATS_RC=1 run sh "$SCRIPT" "${BASE}..HEAD"

    assert_failure
}

@test "test_smoke: budget exhausted warns and exits 0" {
    _commit shell-common/functions/gcp_scan.sh 'g() { :; }'
    printf '#!/bin/sh\nsleep 5\nexit 1\n' >"$SMOKE_BATS"

    PRE_PUSH_SMOKE_BUDGET=1 run sh "$SCRIPT" "${BASE}..HEAD"

    assert_success
    assert_output --partial "budget exhausted"
}

@test "test_smoke: a bats failure reported before the budget cut still fails" {
    _commit shell-common/functions/gcp_scan.sh 'g() { :; }'
    printf '#!/bin/sh\necho "not ok 1 broke"\nsleep 5\n' >"$SMOKE_BATS"

    PRE_PUSH_SMOKE_BUDGET=2 run sh "$SCRIPT" "${BASE}..HEAD"

    assert_failure
    assert_output --partial "budget exhausted"
}
