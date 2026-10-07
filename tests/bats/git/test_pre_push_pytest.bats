#!/usr/bin/env bats
# tests/bats/git/test_pre_push_pytest.bats
#
# Issue #754 / #2046 / #2054 — Layer 0 of git/hooks/pre-push is opt-in:
# by default it runs no tests (one stderr note). PRE_PUSH_TEST=1 runs
# `mise run test-smoke`, PRE_PUSH_FULL_TEST=1 the full `mise run test`.
# Escape paths once opted in:
#   * SKIP_LOCAL_PYTEST=1   explicit opt-out (logged, exit 0)
#   * mise not on PATH      silent skip with one stderr note (exit 0)
#
# Strategy:
#   - Invoke the real hook binary in a sub-bash so it can `exit` without
#     killing the bats process.
#   - Empty stdin makes the per-ref loop a no-op so we only exercise
#     Layer 0.
#   - Mock `mise` via a temp PATH directory; the stub either succeeds,
#     fails loudly, or never gets invoked (assertion by absence).

load '../test_helper'

setup() {
    HOOK="${_BATS_REAL_DOTFILES_ROOT}/git/hooks/pre-push"
    STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-pytest-bats.XXXXXX")"
    STUB_SENTINEL="${STUB_DIR}/.invoked"
}

teardown() {
    if [ -n "${STUB_DIR:-}" ] && [ -d "$STUB_DIR" ]; then
        rm -rf "$STUB_DIR"
    fi
}

# Stub that records every invocation but exits with the requested rc.
_write_mise_stub() {
    local exit_code="$1"
    cat >"${STUB_DIR}/mise" <<EOF
#!/bin/sh
printf '%s\n' "MISE_CALLED: \$* RANGES=\${PRE_PUSH_SMOKE_RANGES:-}" >>'${STUB_SENTINEL}'
exit ${exit_code}
EOF
    chmod +x "${STUB_DIR}/mise"
}

# Run the real hook in a minimal env so the only `mise` resolvable is
# whatever this test prepared.
#   $1   = PATH for the hook invocation
#   $2   = stdin ref lines for the hook (may be empty)
#   $3.. = extra VAR=value env for the hook (e.g. PRE_PUSH_TEST=1)
_run_hook() {
    local path="$1"
    printf '%s' "${2:-}" >"${STUB_DIR}/stdin"
    shift 2
    run env -i \
        PATH="${path}" \
        HOME="${HOME}" \
        SKIP_PRE_PUSH=0 \
        SKIP_LEAK_GUARD=0 \
        "$@" \
        bash -c 'exec bash "$0" origin "https://github.com/owner/repo.git" <"$1" 2>&1' \
        "${HOOK}" "${STUB_DIR}/stdin"
}

# ---------------------------------------------------------------------------
# C0 — default (#2054): no opt-in flag → Layer 0 never calls mise.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: default skips tests without calling mise (#2054)" {
    _write_mise_stub 99

    _run_hook "${STUB_DIR}:/usr/bin:/bin" ""

    assert_success
    assert_output --partial "[pre-push] tests skipped"
    assert_output --partial "PRE_PUSH_TEST=1"
    refute_output --partial "FAIL"
    [ ! -f "$STUB_SENTINEL" ]
}

# ---------------------------------------------------------------------------
# C1 — SKIP_LOCAL_PYTEST=1 short-circuits even with an opt-in flag set.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: SKIP_LOCAL_PYTEST=1 skips the smoke" {
    # Stub that should never be called — if it is, the test fails.
    _write_mise_stub 99

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "" SKIP_LOCAL_PYTEST=1 PRE_PUSH_TEST=1

    assert_success
    assert_output --partial "SKIP_LOCAL_PYTEST=1"
    refute_output --partial "FAIL"
    [ ! -f "$STUB_SENTINEL" ]
}

# ---------------------------------------------------------------------------
# C2 — opted in but mise missing from PATH → silent skip, exit 0.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: mise unavailable silently skips (external contributor compat)" {
    # Defensive guard: if a system-installed `mise` is reachable through
    # /usr/bin or /bin, this test cannot prove the missing-mise branch.
    # Skip rather than produce a misleading pass.
    if PATH="/usr/bin:/bin" command -v mise >/dev/null 2>&1; then
        skip "mise found via /usr/bin or /bin — cannot test mise-missing branch on this host"
    fi

    _run_hook "/usr/bin:/bin" "" PRE_PUSH_TEST=1

    assert_success
    assert_output --partial "mise unavailable"
    refute_output --partial "FAIL"
}

# ---------------------------------------------------------------------------
# C3 — PRE_PUSH_TEST=1 and `mise run test-smoke` succeeds → exit 0.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: PRE_PUSH_TEST=1 runs the smoke, success → exit 0" {
    _write_mise_stub 0

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "" PRE_PUSH_TEST=1

    assert_success
    assert_output --partial "[pre-push] mise run test-smoke"
    refute_output --partial "FAIL"
    [ -f "$STUB_SENTINEL" ]
    run cat "$STUB_SENTINEL"
    assert_output --partial "MISE_CALLED: run test-smoke"
}

# ---------------------------------------------------------------------------
# C4 — PRE_PUSH_TEST=1 and the smoke fails → push aborted (exit 1).
# The opt-in still has to block: a logged-but-ignored failure is no gate.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: PRE_PUSH_TEST=1 and smoke fails → push aborted (exit 1)" {
    _write_mise_stub 1

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "" PRE_PUSH_TEST=1

    assert_failure
    assert_output --partial "mise run test-smoke FAIL — push aborted"
}

# ---------------------------------------------------------------------------
# C5 — PRE_PUSH_FULL_TEST=1 runs the full `mise run test` (#2046, #2054).
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: PRE_PUSH_FULL_TEST=1 runs the full mise run test" {
    _write_mise_stub 0

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "" PRE_PUSH_FULL_TEST=1

    assert_success
    run cat "$STUB_SENTINEL"
    assert_line --regexp "^MISE_CALLED: run test RANGES="
    refute_output --partial "test-smoke"
}

# ---------------------------------------------------------------------------
# C6 — the push range reaches the smoke, and the ref list is still there for
# the per-ref loop afterwards (Layer 1 must still block master).
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: smoke gets the push range; per-ref loop still reads stdin" {
    _write_mise_stub 0
    local a=1111111111111111111111111111111111111111
    local b=2222222222222222222222222222222222222222

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "refs/heads/master ${b} refs/heads/master ${a}
" PRE_PUSH_TEST=1

    assert_failure
    assert_output --partial "master"
    run cat "$STUB_SENTINEL"
    assert_output --partial "RANGES=${a}..${b}"
}

# ---------------------------------------------------------------------------
# C7 — default skip still leaves Layer 1 in force (master blocked, #2054).
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: default skip keeps the protected-branch block" {
    _write_mise_stub 99
    local a=1111111111111111111111111111111111111111
    local b=2222222222222222222222222222222222222222

    _run_hook "${STUB_DIR}:/usr/bin:/bin" "refs/heads/master ${b} refs/heads/master ${a}
"

    assert_failure
    assert_output --partial "master"
    [ ! -f "$STUB_SENTINEL" ]
}
