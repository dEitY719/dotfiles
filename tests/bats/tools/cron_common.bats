#!/usr/bin/env bats
# tests/bats/tools/cron_common.bats
# shell-common/tools/custom/lib/cron_common.sh (issue #2144): the cron lock
# contract and the init.sh TEST_MODE bootstrap it relies on.

load '../test_helper'

TOOLS="${DOTFILES_ROOT}/shell-common/tools/custom"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cron-common.XXXXXX")"
}

teardown() {
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# _lock <snippet> [VAR=VALUE ...] — ux_lib + cron_common, then eval.
_lock() {
    local _snippet="$1"
    shift
    run env "UX_LIB=${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" \
        "LIB=${TOOLS}/lib/cron_common.sh" "D=${_WORK_DIR}/st" "$@" \
        bash -c 'set -u; . "$UX_LIB"; . "$LIB" || exit 99; eval "$1"' _ "${_snippet}"
}

@test "cron_common: a second acquire of a held lock fails and names the tick" {
    # The subshell drops the inherited fd 9 and opens its own.
    _lock 'cron_acquire_lock "$D" .lock my_tick && echo first; ( exec 9>&-; cron_acquire_lock "$D" .lock my_tick; echo "rc=$?" )'
    assert_output --partial "first"
    assert_output --partial "another my_tick tick is already running — skip"
    assert_output --partial "rc=1"
    [ -f "${_WORK_DIR}/st/.lock" ]
}

@test "cron_common: without a tick name a held lock skips silently" {
    _lock 'cron_acquire_lock "$D" .lock; ( exec 9>&-; cron_acquire_lock "$D" .lock; echo "rc=$?" )'
    assert_output "rc=1"
}

@test "cron_common: no flock warns and proceeds unprotected" {
    mkdir -p "${_WORK_DIR}/bin"
    for c in bash mkdir; do ln -s "$(command -v "$c")" "${_WORK_DIR}/bin/$c"; done
    _lock 'cron_acquire_lock "$D" .lock my_tick; echo "rc=$?"' "PATH=${_WORK_DIR}/bin"
    assert_output --partial "flock not found — running without single-instance protection"
    assert_output --partial "rc=0"
}

@test "cron_common: init.sh defines ux_* and SHELL_COMMON under DOTFILES_TEST_MODE" {
    run env -u SHELL_COMMON DOTFILES_TEST_MODE=1 bash -c '. "$1/init.sh"; type ux_info >/dev/null && echo "sc=$SHELL_COMMON"' _ "${TOOLS}"
    assert_success
    assert_output "sc=${DOTFILES_ROOT}/shell-common"
}

@test "cron_common: cron_bootstrap loads init.sh from dirname \$0" {
    # $0 is a path under TOOLS, so dirname "$0" is TOOLS whatever the cwd is.
    run env -u SHELL_COMMON DOTFILES_TEST_MODE=1 bash -c '. "$1/lib/cron_common.sh" && cron_bootstrap && type ux_header >/dev/null && echo "sc=$SHELL_COMMON"' "${TOOLS}/entry.sh" "${TOOLS}"
    assert_success
    assert_output "sc=${DOTFILES_ROOT}/shell-common"
}

@test "cron_common: _hp_acquire_lock lazily sources cron_common when the caller did not" {
    run env "UX_LIB=${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" "LIB=${TOOLS}/lib/herdr_pane.sh" "D=${_WORK_DIR}/st" \
        bash -c 'set -u; . "$UX_LIB"; . "$LIB"; ! type cron_acquire_lock >/dev/null 2>&1 || exit 9; _hp_acquire_lock "$D" .lock t && type cron_acquire_lock >/dev/null && echo ok'
    assert_success
    assert_output "ok"
}
