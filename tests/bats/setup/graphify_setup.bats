#!/usr/bin/env bats
# tests/bats/setup/graphify_setup.bats
# Coverage for graphify/setup.sh + graphify/uninstall.sh (issue #1844):
# soft-fail without the CLI, idempotent account links, never touching a real
# directory or a foreign link, and uninstall removing only our own links.
#
# `graphify` is stubbed on PATH; the stub skill source is pre-created so the
# real `graphify install` never runs.

load '../test_helper'

GRAPHIFY_SETUP="${_BATS_REAL_DOTFILES_ROOT}/graphify/setup.sh"
GRAPHIFY_UNINSTALL="${_BATS_REAL_DOTFILES_ROOT}/graphify/uninstall.sh"

setup() {
    setup_isolated_home
    STUB_BIN="$(mktemp -d)"
    export PATH="${STUB_BIN}:/usr/bin:/bin"
    printf '#!/bin/sh\nexit 0\n' > "${STUB_BIN}/graphify"
    chmod +x "${STUB_BIN}/graphify"
    mkdir -p "$HOME/.claude/skills/graphify"
    touch "$HOME/.claude/skills/graphify/SKILL.md"
    SRC="$HOME/.claude/skills/graphify"
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUB_BIN"
}

@test "setup: missing graphify CLI prints pip guidance and exits 0" {
    rm "${STUB_BIN}/graphify"
    run bash "$GRAPHIFY_SETUP"
    assert_success
    assert_output --partial "pip install graphifyy"
}

@test "setup: links each existing account, is idempotent, skips missing dirs" {
    mkdir -p "$HOME/.claude-work" "$HOME/.claude-work1"
    run bash "$GRAPHIFY_SETUP"
    assert_success
    run bash "$GRAPHIFY_SETUP"
    assert_success
    assert_output --partial "work: link already correct"
    [ "$(readlink "$HOME/.claude-work/skills/graphify")" = "$SRC" ]
    [ "$(readlink "$HOME/.claude-work1/skills/graphify")" = "$SRC" ]
    [ ! -e "$HOME/.claude-personal" ]
}

@test "setup: real directory and foreign link are left alone" {
    mkdir -p "$HOME/.claude-work/skills/graphify" "$HOME/.claude-work1/skills"
    ln -s /nonexistent "$HOME/.claude-work1/skills/graphify"
    run bash "$GRAPHIFY_SETUP"
    assert_success
    [ -d "$HOME/.claude-work/skills/graphify" ] && [ ! -L "$HOME/.claude-work/skills/graphify" ]
    [ "$(readlink "$HOME/.claude-work1/skills/graphify")" = "/nonexistent" ]
}

@test "setup: internal mode skips account links" {
    echo internal > "$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude-work"
    run bash "$GRAPHIFY_SETUP"
    assert_success
    [ ! -e "$HOME/.claude-work/skills/graphify" ]
}

@test "uninstall: removes only links to the source, keeps real dirs" {
    mkdir -p "$HOME/.claude-work/skills/graphify" "$HOME/.claude-work1/skills"
    ln -s "$SRC" "$HOME/.claude-work1/skills/graphify"
    run bash "$GRAPHIFY_UNINSTALL"
    assert_success
    [ ! -L "$HOME/.claude-work1/skills/graphify" ]
    [ -d "$HOME/.claude-work/skills/graphify" ]
    [ -f "$SRC/SKILL.md" ]
    assert_output --partial "graphify uninstall --purge"
}
