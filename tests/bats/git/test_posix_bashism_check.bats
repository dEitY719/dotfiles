#!/usr/bin/env bats
# tests/bats/git/test_posix_bashism_check.bats
# git/hooks/checks/posix_bashism_check.sh must allow the sanctioned
# shell-detection test (`[ -n "${BASH_VERSION-}" ]`) but keep flagging real
# bash-only ${BASH_*} reads in #!/bin/sh files (#2189).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/git/hooks/checks/posix_bashism_check.sh"
    F="$BATS_TEST_TMPDIR/f.sh"
    OUT="$BATS_TEST_TMPDIR/violations"
    : >"$OUT"
}

_write() { printf '#!/bin/sh\n%s\n' "$1" >"$F"; }

@test "posix_bashism: shell-detection idioms pass" {
    for line in \
        'if [ -n "${BASH_VERSION-}" ]; then' \
        'if [ -n "${BASH_VERSION:-}" ]; then' \
        '[ -z "${BASH_VERSION}" ] && :' \
        'elif [ -n "${BASH_VERSION-}" ]; then'; do
        _write "$line"
        run check_posix_bashism "$F" f.sh "$OUT"
        [ "$status" -eq 0 ] || { echo "flagged: $line"; false; }
    done
    [ ! -s "$OUT" ]
}

@test "posix_bashism: BASH_SOURCE array read is a violation" {
    _write 'd=$(dirname "${BASH_SOURCE[0]}")'
    run check_posix_bashism "$F" f.sh "$OUT"
    [ "$status" -eq 1 ]
    grep -q '^f.sh:2:' "$OUT"
}

@test "posix_bashism: BASH_REMATCH read is a violation" {
    _write 'm=${BASH_REMATCH[1]}'
    run check_posix_bashism "$F" f.sh "$OUT"
    [ "$status" -eq 1 ]
}

@test "posix_bashism: detection test does not mask another read on the same line" {
    _write '[ -n "${BASH_VERSION-}" ] && d=${BASH_SOURCE[0]}'
    run check_posix_bashism "$F" f.sh "$OUT"
    [ "$status" -eq 1 ]
}

@test "posix_bashism: BASH_VERSION outside a test is still a violation" {
    _write 'v=${BASH_VERSION}'
    run check_posix_bashism "$F" f.sh "$OUT"
    [ "$status" -eq 1 ]
}
