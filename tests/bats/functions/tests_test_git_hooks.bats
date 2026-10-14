#!/usr/bin/env bats
# tests/bats/functions/tests_test_git_hooks.bats
# Unit tests for tests/test's git hook phase (#2133).
#
# git/tests/*.sh (test_hooks.sh, test-pre-push.sh, test-prepare-commit-msg.sh)
# used to run only by hand; run_git_hook_tests() now runs them from
# ./tests/test with an isolated HOME / global git config and a per-script
# wall clock cap (GIT_HOOK_TEST_TIMEOUT). These tests drive the phase over
# fake scripts (GIT_HOOK_TESTS_DIR) — the real scripts take ~1-4 min.
#
# tests/test guards its `main "$@"` call, so sourcing it is side-effect free.

load '../test_helper'

RUNNER="${BATS_TEST_DIRNAME}/../../test"
REAL_REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
    setup_isolated_home
    # shellcheck source=/dev/null
    source "$RUNNER"
    VERBOSE=0
    unset GIT_HOOK_TEST_TIMEOUT
    FAKE_DIR="$TEST_TEMP_HOME/hooks"
    WORK="$TEST_TEMP_HOME/work"
    mkdir -p "$FAKE_DIR" "$WORK"
    export GIT_HOOK_TESTS_DIR="$FAKE_DIR"
}

teardown() {
    unset GIT_HOOK_TESTS_DIR
    teardown_isolated_home
}

# fake_script <name> <body>
fake_script() {
    printf '#!/bin/bash\n%s\n' "$2" >"$FAKE_DIR/$1"
}

@test "the three hook scripts live in git/tests/ and git/test/ is gone" {
    unset GIT_HOOK_TESTS_DIR
    # Tracked files only: an untracked leftover (editor swap, cache) can keep
    # an old git/test/ dir alive in a dev checkout after the move.
    [ -z "$(git -C "$REAL_REPO" ls-files -- git/test 2>/dev/null)" ]
    run _discover_git_hook_tests
    assert_success
    assert_output --partial "/git/tests/test_hooks.sh"
    assert_output --partial "/git/tests/test-pre-push.sh"
    assert_output --partial "/git/tests/test-prepare-commit-msg.sh"
}

@test "_resolve_git_hook_timeout: defaults to 600, honors a positive override" {
    run _resolve_git_hook_timeout
    assert_output "600"
    GIT_HOOK_TEST_TIMEOUT=42 run _resolve_git_hook_timeout
    assert_output "42"
    GIT_HOOK_TEST_TIMEOUT=abc run _resolve_git_hook_timeout
    assert_output "600"
}

@test "run_git_hook_tests: all scripts passing -> success + summary" {
    fake_script a.sh 'echo a-ran'
    fake_script b.sh 'echo b-ran'
    run run_git_hook_tests "$WORK"
    assert_success
    assert_output --partial "git hooks: 2 scripts passed"
    # Passing output is buffered, not printed (only -v shows it).
    refute_output --partial "a-ran"
}

@test "run_git_hook_tests: a failing script fails the phase and prints its log" {
    fake_script a.sh 'echo fine'
    fake_script b.sh 'echo boom-detail; exit 3'
    run run_git_hook_tests "$WORK"
    assert_failure
    assert_output --partial "FAILED:"
    assert_output --partial "b.sh"
    assert_output --partial "boom-detail"
    assert_output --partial "1 of 2 scripts failed"
}

@test "run_git_hook_tests: no scripts found fails closed" {
    run run_git_hook_tests "$WORK"
    assert_failure
    assert_output --partial "No git hook test scripts found"
}

@test "scripts run with an isolated HOME and empty global git config" {
    local real_home="$HOME"
    fake_script iso.sh '
[ "$HOME" != "'"$real_home"'" ] || { echo "HOME not isolated"; exit 1; }
[ "$GIT_CONFIG_NOSYSTEM" = "1" ] || { echo "system config not disabled"; exit 1; }
[ -z "$(git config --global --list 2>/dev/null)" ] || { echo "global config not empty"; exit 1; }
git config --global user.name probe
[ "$(git config --global user.name)" = probe ] || exit 1'
    run run_git_hook_tests "$WORK"
    assert_success
    # The script's global write landed in its own HOME, not the caller's.
    [ ! -e "$real_home/.gitconfig" ]
}

@test "each script gets its own HOME: a global git write does not reach the next" {
    # Discovery is glob-ordered: a.sh runs before b.sh.
    fake_script a.sh 'git config --global user.name leaked-from-a'
    fake_script b.sh '[ -z "$(git config --global user.name)" ] || { echo "HOME shared"; exit 1; }'
    run run_git_hook_tests "$WORK"
    assert_success
    assert_output --partial "git hooks: 2 scripts passed"
}

@test "a 137 exit before the cap is reported as a failure, not a timeout" {
    fake_script oom.sh 'exit 137'
    GIT_HOOK_TEST_TIMEOUT=600 run run_git_hook_tests "$WORK"
    assert_failure
    refute_output --partial "killed after GIT_HOOK_TEST_TIMEOUT"
}

# run_tests wiring: stub the other phases so only the git hook phase decides
# the result, then check both the parallel and the sequential path.
_stub_other_phases() {
    run_bats() { echo "stub-bats"; }
    run_golden_rules() { echo "stub-golden"; }
    run_pytest() { echo "stub-pytest"; }
}

@test "run_tests (parallel): a failing hook script fails the run and its log is printed" {
    _stub_other_phases
    fake_script bad.sh 'echo hook-phase-detail; exit 1'
    SERIAL=0 TEST_PHASES_SEQUENTIAL=0 run run_tests
    assert_failure
    assert_output --partial "Running Git Hook Tests"
    assert_output --partial "hook-phase-detail"
    assert_output --partial "stub-pytest"
}

@test "run_tests (TEST_PHASES_SEQUENTIAL=1): hook phase runs and gates the result" {
    _stub_other_phases
    fake_script bad.sh 'exit 1'
    SERIAL=0 TEST_PHASES_SEQUENTIAL=1 run run_tests
    assert_failure
    assert_output --partial "FAILED:"
    fake_script bad.sh 'exit 0'
    SERIAL=0 TEST_PHASES_SEQUENTIAL=1 run run_tests
    assert_success
    assert_output --partial "git hooks: 1 scripts passed"
}

@test "scripts never inherit a hook's GIT_DIR or leak-guard escape hatches" {
    fake_script env.sh '
[ -z "${GIT_DIR+x}" ] || { echo "GIT_DIR leaked: $GIT_DIR"; exit 1; }
[ -z "${GIT_INDEX_FILE+x}" ] || { echo "GIT_INDEX_FILE leaked"; exit 1; }
[ -z "${SKIP_LEAK_GUARD+x}" ] || { echo "SKIP_LEAK_GUARD leaked"; exit 1; }
[ -z "${PRE_PUSH_FULL_TEST+x}" ] || { echo "PRE_PUSH_FULL_TEST leaked"; exit 1; }'
    GIT_DIR=/nonexistent/.git GIT_INDEX_FILE=/nonexistent/index \
        SKIP_LEAK_GUARD=1 PRE_PUSH_FULL_TEST=1 run run_git_hook_tests "$WORK"
    assert_success
}

@test "GIT_HOOK_TEST_TIMEOUT kills a hung script and fails the phase" {
    command -v timeout >/dev/null 2>&1 || skip "timeout(1) not available"
    fake_script hang.sh 'exec sleep 30'
    SECONDS=0
    GIT_HOOK_TEST_TIMEOUT=1 run run_git_hook_tests "$WORK"
    assert_failure
    assert_output --partial "killed after GIT_HOOK_TEST_TIMEOUT=1s"
    ((SECONDS < 20)) || false
}

# #2165: a hung script's background child must die with it on timeout.
@test "GIT_HOOK_TEST_TIMEOUT also kills a hung script's grandchildren" {
    command -v timeout >/dev/null 2>&1 || skip "timeout(1) not available"
    local mark=$((300000 + RANDOM))
    fake_script hang.sh "sleep $mark &
exec sleep 30"
    GIT_HOOK_TEST_TIMEOUT=1 run run_git_hook_tests "$WORK"
    assert_output --partial "killed after GIT_HOOK_TEST_TIMEOUT=1s"
    local i
    for i in $(seq 1 30); do
        pgrep -f "sleep $mark" >/dev/null || break
        sleep 0.1
    done
    run pgrep -f "sleep $mark"
    pkill -f "sleep $mark" 2>/dev/null || true
    assert_failure
}

# #2165: timeout's own process group sits outside the phase group, so an
# interrupt reaches a hung script's tree only through the _TEST_TREE_DIR
# registry that _kill_test_groups reads.
@test "SIGTERM to the runner kills a running hook script's whole tree" {
    command -v timeout >/dev/null 2>&1 || skip "timeout(1) not available"
    local mark=$((300000 + RANDOM)) i pid
    fake_script hang.sh "sleep $mark &
exec sleep $((mark + 1))"
    set -m
    TMPDIR="$TEST_TEMP_HOME" bash -c "source '$RUNNER'; VERBOSE=0
        _install_test_traps; _run_in_group run_git_hook_tests '$WORK'" \
        >/dev/null 2>&1 </dev/null 3>&- &
    pid=$!
    set +m
    for i in $(seq 1 50); do
        pgrep -f "sleep $((mark + 1))" >/dev/null && break
        sleep 0.1
    done
    kill -TERM "$pid"
    for i in $(seq 1 50); do
        pgrep -f "sleep $mark|sleep $((mark + 1))" >/dev/null || break
        sleep 0.1
    done
    run pgrep -f "sleep $mark|sleep $((mark + 1))"
    pkill -f "sleep $mark|sleep $((mark + 1))" 2>/dev/null || true
    assert_failure
}
