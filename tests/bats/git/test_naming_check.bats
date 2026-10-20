#!/usr/bin/env bats
# tests/bats/git/test_naming_check.bats
#
# Unit cases for git/hooks/checks/naming_check.sh check_naming_violations
# (#2255): a one-line thin wrapper that runs "${SHELL_COMMON...}"/tools/custom/
# <name>.sh is a command, not user-facing text, and must not be reported as a
# dash-form miss; text that merely mentions the path still is.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/git/hooks/checks/naming_check.sh"
    F="$BATS_TEST_TMPDIR/demo_tool.sh"
    OUT="$BATS_TEST_TMPDIR/violations"
    : >"$OUT"
}

# _write <body line>... -- one file defining demo_tool() with those body lines.
_write() {
    {
        printf 'demo_tool() {\n'
        printf '    %s\n' "$@"
        printf '}\n'
    } >"$F"
}

_assert_clean() {
    run check_naming_violations "$F" "$OUT"
    [ "$status" -eq 0 ] || { cat "$OUT"; false; }
    [ ! -s "$OUT" ]
}

_assert_flagged() {
    run check_naming_violations "$F" "$OUT"
    [ "$status" -eq 1 ]
    grep -qF "$1" "$OUT"
}

@test "one-line wrapper calling tools/custom/<name>.sh is not a violation" {
    _write '"${SHELL_COMMON:-$HOME/dotfiles/shell-common}"/tools/custom/demo_tool.sh "$@"'
    _assert_clean
}

@test "wrapper with a fixed argument (teardown / --help) is not a violation" {
    _write '"${SHELL_COMMON:-$HOME/dotfiles/shell-common}"/tools/custom/demo_tool.sh teardown "$@"'
    _assert_clean
    _write '"${SHELL_COMMON:-$HOME/dotfiles/shell-common}"/tools/custom/demo_tool.sh --help'
    _assert_clean
}

@test "snake_case name inside user-facing text is still a violation" {
    _write "printf '%s\\n' \"run demo_tool to start\""
    _assert_flagged 'run demo_tool to start'
}

@test "user-facing text that merely mentions tools/custom/<name>.sh is still a violation" {
    _write "printf '%s\\n' \"demo_tool failed: see tools/custom/demo_tool.sh\""
    _assert_flagged 'see tools/custom/demo_tool.sh'
}

@test "text quoting the wrapper path after a colon is still a violation" {
    _write "printf '%s\\n' \"demo_tool failed: \"\${SHELL_COMMON}\"/tools/custom/demo_tool.sh\""
    _assert_flagged 'demo_tool failed:'
}

@test "wrapper whose path contains another function's name is not a violation" {
    # secret_run.sh shape: `demo` (an inner helper) is a prefix of demo_tool.sh.
    _write '"${SHELL_COMMON:-$HOME/dotfiles/shell-common}"/tools/custom/demo_tool.sh "$@"'
    printf 'demo() { demo_tool "$@"; }\n' >>"$F"
    _assert_clean
}
