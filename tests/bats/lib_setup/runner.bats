#!/usr/bin/env bats
# tests/bats/lib_setup/runner.bats
# shell-common/lib/setup/runner.sh (#2137) must expose the very runner root
# setup.sh uses (shell-common/tools/ux_lib/step_runner.sh, #2126): same
# functions, byte-identical step output. tests/bats/setup/setup_runner.bats
# keeps covering the runner's own contract.

load '../test_helper'

RUNNER_LIB="${_BATS_REAL_SHELL_COMMON}/lib/setup/runner.sh"
ROOT_SETUP="${_BATS_REAL_DOTFILES_ROOT}/setup.sh"

setup() {
    setup_isolated_home
    STUBS="$(mktemp -d)"
    printf '#!/bin/sh\necho noisy detail\n' >"$STUBS/ok.sh"
    printf '#!/bin/sh\necho "⚠️  경고: fix me with X"\n' >"$STUBS/warn.sh"
    printf '#!/bin/sh\necho boom-detail\nexit 3\n' >"$STUBS/bad.sh"
    chmod +x "$STUBS"/*.sh
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUBS"
}

# Run the same step sequence under one runner source; elapsed times masked.
_steps() {
    bash -c "source '$1'; STEP_LOG='$STUBS/log'; STEP_OUT='$STUBS/step'
        step_run first critical '$STUBS/ok.sh'
        step_run second optional '$STUBS/warn.sh'
        step_run third optional '$STUBS/bad.sh'
        step_summary demo" 2>&1 | sed -E 's/[0-9]+\.[0-9]s/T/g'
}

@test "runner lib: defines the step_* API" {
    run bash -c "source '$RUNNER_LIB'; declare -F step_init step_run step_summary"
    assert_success
    assert_equal "${#lines[@]}" 3
}

@test "runner lib: output is byte-identical to root setup.sh's runner" {
    lib_out=$(_steps "$RUNNER_LIB")
    root_out=$(_steps "$ROOT_SETUP")
    [ -n "$lib_out" ]
    assert_equal "$lib_out" "$root_out"
}
