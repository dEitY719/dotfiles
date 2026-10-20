#!/usr/bin/env bats
# tests/bats/git/test_naming_check.bats
#
# Unit cases for git/hooks/checks/naming_check.sh check_naming_violations
# (#2255): a one-line thin wrapper that runs tools/custom/<name>.sh "$@" is a
# path, not user-facing text, and must not be reported as a dash-form miss.

load '../test_helper'

setup() {
    # shellcheck source=/dev/null
    . "${BATS_TEST_DIRNAME}/../../../git/hooks/checks/naming_check.sh"
    out="${BATS_TEST_TMPDIR}/violations"
    : >"$out"
}

@test "one-line wrapper calling tools/custom/<name>.sh is not a violation" {
    f="${BATS_TEST_TMPDIR}/demo_tool.sh"
    cat >"$f" <<'SH'
demo_tool() {
    "${SHELL_COMMON:-$HOME/dotfiles/shell-common}"/tools/custom/demo_tool.sh "$@"
}
SH
    run check_naming_violations "$f" "$out"
    [ "$status" -eq 0 ]
    [ ! -s "$out" ]
}

@test "snake_case name inside user-facing text is still a violation" {
    f="${BATS_TEST_TMPDIR}/demo_tool.sh"
    cat >"$f" <<'SH'
demo_tool() {
    printf '%s\n' "run demo_tool to start"
}
SH
    run check_naming_violations "$f" "$out"
    [ "$status" -eq 1 ]
    grep -q 'run demo_tool to start' "$out"
}
