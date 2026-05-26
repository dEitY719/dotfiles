#!/usr/bin/env bats
# tests/bats/git/test_pre_push_pytest.bats
#
# Issue #754 — Layer 0 of git/hooks/pre-push runs `mise run test` once
# per push, with two escape paths:
#   * SKIP_LOCAL_PYTEST=1   explicit opt-out (logged, exit 0)
#   * mise not on PATH      silent skip with one stderr note (exit 0)
#
# Strategy:
#   - Invoke the real hook binary in a sub-bash so it can `exit` without
#     killing the bats process.
#   - Empty stdin (`</dev/null`) makes the per-ref loop a no-op so we
#     only exercise Layer 0.
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
printf '%s\n' "MISE_CALLED: \$*" >>'${STUB_SENTINEL}'
exit ${exit_code}
EOF
    chmod +x "${STUB_DIR}/mise"
}

# Run the real hook in a minimal env so the only `mise` resolvable is
# whatever this test prepared.
#   $1 = PATH for the hook invocation
#   $2 = SKIP_LOCAL_PYTEST value (default 0)
_run_hook() {
    local path="$1"
    local skip="${2:-0}"
    run bash -c "
        env -i \
            PATH='${path}' \
            HOME='${HOME}' \
            SKIP_PRE_PUSH=0 \
            SKIP_LEAK_GUARD=0 \
            SKIP_LOCAL_PYTEST='${skip}' \
            bash '${HOOK}' origin 'https://github.com/owner/repo.git' </dev/null 2>&1
    "
}

# ---------------------------------------------------------------------------
# C1 — SKIP_LOCAL_PYTEST=1 short-circuits before mise is ever invoked.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: SKIP_LOCAL_PYTEST=1 skips mise run test" {
    # Stub that should never be called — if it is, the test fails.
    _write_mise_stub 99

    _run_hook "${STUB_DIR}:/usr/bin:/bin" 1

    assert_success
    assert_output --partial "SKIP_LOCAL_PYTEST=1"
    refute_output --partial "mise run test FAIL"
    [ ! -f "$STUB_SENTINEL" ]
}

# ---------------------------------------------------------------------------
# C2 — mise missing from PATH → silent skip, exit 0.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: mise unavailable silently skips (external contributor compat)" {
    # Defensive guard: if a system-installed `mise` is reachable through
    # /usr/bin or /bin, this test cannot prove the missing-mise branch.
    # Skip rather than produce a misleading pass.
    if PATH="/usr/bin:/bin" command -v mise >/dev/null 2>&1; then
        skip "mise found via /usr/bin or /bin — cannot test mise-missing branch on this host"
    fi

    _run_hook "/usr/bin:/bin" 0

    assert_success
    assert_output --partial "mise unavailable"
    refute_output --partial "mise run test FAIL"
}

# ---------------------------------------------------------------------------
# C3 — mise present and `mise run test` succeeds → exit 0 (정상 실행).
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: mise present and test succeeds → exit 0" {
    _write_mise_stub 0

    _run_hook "${STUB_DIR}:/usr/bin:/bin" 0

    assert_success
    assert_output --partial "mise run test (set SKIP_LOCAL_PYTEST=1 to bypass)"
    refute_output --partial "FAIL"
    [ -f "$STUB_SENTINEL" ]
    run cat "$STUB_SENTINEL"
    assert_output --partial "MISE_CALLED: run test"
}

# ---------------------------------------------------------------------------
# C4 — mise present and `mise run test` fails → push aborted (exit 1).
# This is the policy-enforcing assertion: without it, Layer 0 would
# silently log but not block a regression-laden push.
# ---------------------------------------------------------------------------
@test "pre-push Layer 0: mise present and test fails → push aborted (exit 1)" {
    _write_mise_stub 1

    _run_hook "${STUB_DIR}:/usr/bin:/bin" 0

    assert_failure
    assert_output --partial "mise run test FAIL — push aborted"
}
