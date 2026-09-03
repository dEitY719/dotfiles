#!/usr/bin/env bats
# tests/bats/lint/command_docs_staleness_check.bats
# Issue #1737 — warn (never block) when shell-common/tools/custom/*.sh is
# staged without docs/guide/commands/mytool.md.

load '../test_helper'

CHECK_PATH="${_BATS_REAL_DOTFILES_ROOT}/git/hooks/checks/command_docs_staleness_check.sh"

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    . "$CHECK_PATH"
    WARN_FILE="$(mktemp "$BATS_TEST_TMPDIR/warn.XXXXXX")"
}

teardown() {
    [ -n "$WARN_FILE" ] && rm -f "$WARN_FILE"
    teardown_isolated_home
}

@test "new tools/custom script without doc update is flagged" {
    local staged=$'shell-common/tools/custom/new_tool.sh\nshell-common/functions/foo.sh'
    run check_command_docs_staleness "$staged" "$WARN_FILE"
    [ "$status" -eq 1 ]
    grep -q 'docs/guide/commands/mytool.md' "$WARN_FILE"
}

@test "tools/custom script staged together with doc update is silent" {
    local staged=$'shell-common/tools/custom/new_tool.sh\ndocs/guide/commands/mytool.md'
    run check_command_docs_staleness "$staged" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "commit without any tools/custom change is silent" {
    local staged=$'shell-common/functions/foo.sh\ndocs/guide/README.md'
    run check_command_docs_staleness "$staged" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "tools/custom subdirectory helper (not top-level entrypoint) still matches by path" {
    local staged='shell-common/tools/custom/subdir/helper.sh'
    run check_command_docs_staleness "$staged" "$WARN_FILE"
    [ "$status" -eq 1 ]
}

@test "deleted tools/custom script without doc update is flagged (codex review, PR #1741)" {
    # pre-commit's STAGED_FILES (--diff-filter=ACMR) excludes deletions, so
    # this check must be fed a deletion-inclusive file list — this test
    # asserts the check itself still fires when a deleted path is present.
    local staged=$'shell-common/tools/custom/removed_tool.sh\nshell-common/functions/foo.sh'
    run check_command_docs_staleness "$staged" "$WARN_FILE"
    [ "$status" -eq 1 ]
}
