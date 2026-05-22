#!/usr/bin/env bats
# tests/bats/functions/claude_compose_skills_dir.bats
# Cover _claude_compose_skills_dir — the F-8 / issue #707 helper that
# converts the legacy directory-level skills symlink into a real
# directory of entry-level symlinks. Companion overlay coverage lives
# in setup_company_skills.bats.

load '../test_helper'

setup() {
    setup_isolated_home
    SRC="$TEST_TEMP_HOME/src-skills"
    TGT="$TEST_TEMP_HOME/.claude/skills"

    mkdir -p "$SRC/alpha" "$SRC/beta"
    : > "$SRC/alpha/SKILL.md"
    : > "$SRC/beta/SKILL.md"

    HELPER_SCRIPT="$(mktemp "$TEST_TEMP_HOME/run.XXXXXX.sh")"
    cat > "$HELPER_SCRIPT" <<EOF
#!/bin/bash
set -e
export DOTFILES_FORCE_INIT=1
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/mount.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
_claude_compose_skills_dir "\$1" "\$2"
EOF
    chmod +x "$HELPER_SCRIPT"
}

teardown() {
    teardown_isolated_home
}

@test "creates entry-level symlinks for each skill subdir" {
    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -L "$TGT/alpha" ] && [ "$(readlink "$TGT/alpha")" = "$SRC/alpha" ]
    [ -L "$TGT/beta" ]  && [ "$(readlink "$TGT/beta")"  = "$SRC/beta" ]
}

@test "migrates legacy dir-symlink to real dir + entry composition" {
    mkdir -p "$(dirname "$TGT")"
    ln -s "$SRC" "$TGT"
    [ -L "$TGT" ]

    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -L "$TGT/alpha" ] && [ "$(readlink "$TGT/alpha")" = "$SRC/alpha" ]
}

@test "is idempotent on repeat runs" {
    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success
    before="$(ls -la "$TGT")"

    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success
    after="$(ls -la "$TGT")"

    [ "$before" = "$after" ]
}

@test "prunes stale dotfiles entries whose source was removed" {
    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    rm -rf "$SRC/beta"
    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    [ -L "$TGT/alpha" ]
    [ ! -e "$TGT/beta" ]
}

@test "preserves overlay symlinks pointing outside the source" {
    OVERLAY="$TEST_TEMP_HOME/overlay-skills"
    mkdir -p "$OVERLAY/gamma"
    : > "$OVERLAY/gamma/SKILL.md"

    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success
    ln -s "$OVERLAY/gamma" "$TGT/gamma"

    run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    [ -L "$TGT/gamma" ] && [ "$(readlink "$TGT/gamma")" = "$OVERLAY/gamma" ]
}
