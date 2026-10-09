#!/usr/bin/env bats
# tests/bats/git/test_help_integrity_check.bats
# git/hooks/checks/help_integrity_check.sh must actually detect unregistered
# public *_help functions. Its grep/sed patterns were over-escaped (`\\(` inside
# single quotes), so the check silently matched nothing and never fired.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/git/hooks/checks/help_integrity_check.sh"
    FAKE_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_ROOT/shell-common/functions"
    printf '_register_help registered_help "desc" Meta\n' \
        >"$FAKE_ROOT/shell-common/functions/my_help.sh"
    VIOLATIONS="$BATS_TEST_TMPDIR/violations"
    : >"$VIOLATIONS"
}

@test "help_integrity: unregistered public help function is a violation" {
    f="$FAKE_ROOT/shell-common/functions/orphan.sh"
    printf 'orphan_help() {\n    :\n}\nfunction other_help {\n    :\n}\n' >"$f"
    run check_help_integrity "$f" "$VIOLATIONS" "$FAKE_ROOT"
    [ "$status" -eq 1 ]
    grep -q "'orphan_help'" "$VIOLATIONS"
    grep -q "'other_help'" "$VIOLATIONS"
}

@test "help_integrity: registered and internal help functions pass" {
    f="$FAKE_ROOT/shell-common/functions/ok.sh"
    printf 'registered_help() {\n    :\n}\n_internal_help() {\n    :\n}\n' >"$f"
    run check_help_integrity "$f" "$VIOLATIONS" "$FAKE_ROOT"
    [ "$status" -eq 0 ]
    [ ! -s "$VIOLATIONS" ]
}

@test "help_integrity: every shell-common/functions file in the repo passes" {
    for f in "$REPO_ROOT"/shell-common/functions/*.sh; do
        check_help_integrity "$f" "$VIOLATIONS" "$REPO_ROOT" || true
    done
    [ ! -s "$VIOLATIONS" ] || { cat "$VIOLATIONS"; false; }
}
