#!/usr/bin/env bats
# tests/bats/lint/bare_wait.bats
# Issue #2054 — an argument-less `wait` inside a bats test is a guaranteed
# BATS_TEST_TIMEOUT (300s) failure: bats-exec-test starts its timeout
# watchdog as a background job of the test shell, so a bare `wait` blocks on
# the watchdog itself. Wait on explicit PIDs (`wait "$!"`) instead.
# lib/ is the vendored bats-core submodule and stays out of scope.

load '../test_helper'

# A bare `wait` statement: preceded by start/separator/keyword, followed by
# end/separator/comment/redirect — never by an operand.
BARE_WAIT_ERE='(^|[;&|({]|then|do|else)[[:space:]]*wait[[:space:]]*($|[;&|#)}]|[0-9]*>)'

@test "no bats test uses an argument-less wait" {
    # Positive control: the pattern must catch the bare forms and spare
    # PID-bearing / -n forms, or the scan below proves nothing.
    run grep -cE "$BARE_WAIT_ERE" <<'EOF'
    wait
    _spawn x & wait
    wait 2>/dev/null
    wait "$!"
    wait -n
    wait "${pids[@]}"
EOF
    assert_output "3"

    run grep -rnE "$BARE_WAIT_ERE" --include='*.bats' --include='*.bash' \
        --exclude-dir=lib --exclude=bare_wait.bats \
        "${_BATS_REAL_DOTFILES_ROOT}/tests/bats"
    assert_output ""
}
