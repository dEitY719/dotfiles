#!/usr/bin/env bats
# tests/bats/tools/check_ux_consistency.bats
# Regression coverage for issue #1942: the checker referenced an undefined
# ${SCRIPT_DIR} and stale bash/ dirs, so it scanned zero files and always passed.
# The script resolves its roots from its own realpath, so it runs from a fixture
# tree: <fixture>/shell-common/tools/{custom,ux_lib}.

load '../test_helper'

REAL_SC="${DOTFILES_ROOT}/shell-common"

setup() {
    setup_isolated_home
    FIX="${TEST_TEMP_HOME}/fixture"
    mkdir -p "${FIX}/shell-common/tools/custom" "${FIX}/shell-common/tools/ux_lib" "${FIX}/zsh"
    cp "${REAL_SC}/tools/custom/check_ux_consistency.sh" "${FIX}/shell-common/tools/custom/"
    cp "${REAL_SC}/tools/ux_lib/ux_lib.sh" "${FIX}/shell-common/tools/ux_lib/"
    SCRIPT="${FIX}/shell-common/tools/custom/check_ux_consistency.sh"
}

teardown() {
    teardown_isolated_home
}

@test "check_ux_consistency: scans a non-zero number of files in the fixture tree" {
    printf 'ux_info "hi"\n' >"${FIX}/shell-common/clean.sh"
    printf 'ux_info "hi"\n' >"${FIX}/zsh/clean.zsh"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Scanned 2 file(s)"* ]]
}

@test "check_ux_consistency: detects deprecated tput colors under shell-common" {
    # shellcheck disable=SC2016
    printf 'red=$(tput setaf 1)\n' >"${FIX}/shell-common/bad.sh"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bad.sh"* ]]
}

@test "check_ux_consistency: fails when no files are scanned" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Scanned 0 file(s)"* ]]
}

@test "check_ux_consistency: flags non-executable python helpers in shell-common/tools/ux_lib" {
    printf 'x\n' >"${FIX}/shell-common/clean.sh"
    : >"${FIX}/shell-common/tools/ux_lib/helper.py"
    chmod -x "${FIX}/shell-common/tools/ux_lib/helper.py"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"helper.py"* ]]
}
