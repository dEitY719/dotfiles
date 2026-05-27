#!/usr/bin/env bats
# tests/bats/functions/setup_opencode_config.bats
# Verify setup_opencode_config preserves user-edited Knox ID across re-runs
# (issue #792). Three scenarios mirror the issue's acceptance criteria:
#   1. fresh install (no target)        — cp template, no backup
#   2. re-run with placeholder unchanged — cp template again (current behavior)
#   3. re-run with Knox ID customised   — preserve, no backup spam

load '../test_helper'

setup() {
    setup_isolated_home

    # Build a tiny dotfiles fixture so the function's cp source resolves.
    FIXTURE_DOTFILES="$TEST_TEMP_HOME/dotfiles"
    mkdir -p \
        "$FIXTURE_DOTFILES/opencode" \
        "$FIXTURE_DOTFILES/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/opencode/opencode.json.internal" \
       "$FIXTURE_DOTFILES/opencode/opencode.json.internal"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" \
       "$FIXTURE_DOTFILES/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" \
       "$FIXTURE_DOTFILES/shell-common/setup.sh"

    TARGET="$HOME/.config/opencode/opencode.json"
    mkdir -p "$(dirname "$TARGET")"
}

teardown() {
    teardown_isolated_home
}

# Source setup.sh in a subshell, then invoke setup_opencode_config alone.
# The direct-exec guard in setup.sh prevents main() from prompting.
run_setup_opencode() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        setup_opencode_config internal
    "
}

count_backups() {
    ls "${TARGET}.backup."* 2>/dev/null | wc -l
}

@test "fresh install: copies template when target does not exist" {
    run_setup_opencode
    assert_success
    [ -f "$TARGET" ]
    grep -q 'your-knox-id' "$TARGET"
    [ "$(count_backups)" -eq 0 ]
}

@test "re-run with placeholder unchanged: re-copies template" {
    run_setup_opencode
    assert_success

    run_setup_opencode
    assert_success
    [ -f "$TARGET" ]
    grep -q 'your-knox-id' "$TARGET"
}

@test "re-run with Knox ID customised: preserves file, creates no backup" {
    run_setup_opencode
    assert_success

    # User replaces the placeholder with a real Knox ID. Use a temp-file
    # rewrite (not `sed -i`) — GNU sed and BSD sed disagree on the `-i`
    # argument syntax, so the in-place form breaks on macOS dev machines.
    sed 's/your-knox-id/abc123knox/' "$TARGET" > "${TARGET}.tmp" \
        && mv "${TARGET}.tmp" "$TARGET"
    customised_content="$(cat "$TARGET")"

    run_setup_opencode
    assert_success
    assert_output --partial "Preserved customised OpenCode config"

    # File untouched.
    [ "$(cat "$TARGET")" = "$customised_content" ]
    # No backup spam.
    [ "$(count_backups)" -eq 0 ]
}

@test "stray external-mode symlink at target: overwritten with template copy" {
    # Simulate user switching from external (symlink) to internal mode.
    ln -s "$FIXTURE_DOTFILES/opencode/opencode.json.internal" "$TARGET"

    run_setup_opencode
    assert_success

    [ -f "$TARGET" ]
    [ ! -L "$TARGET" ]
    grep -q 'your-knox-id' "$TARGET"
}
