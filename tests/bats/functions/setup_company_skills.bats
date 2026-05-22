#!/usr/bin/env bats
# tests/bats/functions/setup_company_skills.bats
# Cover scripts/setup-company-skills.sh — the issue #707 private skills
# overlay that layers $COMPANY_SKILLS_HOME entries into ~/.claude*/skills/.
# Companion F-8 coverage lives in claude_compose_skills_dir.bats.

load '../test_helper'

SCRIPT_REL="scripts/setup-company-skills.sh"

setup() {
    setup_isolated_home
    SCRIPT="${_BATS_REAL_DOTFILES_ROOT}/${SCRIPT_REL}"
    SKILLS_DIR="$HOME/.claude/skills"
}

teardown() {
    teardown_isolated_home
}

run_overlay() {
    run env COMPANY_SKILLS_HOME="$1" HOME="$HOME" bash "$SCRIPT"
}

@test "exits 0 with info when COMPANY_SKILLS_HOME missing" {
    mkdir -p "$SKILLS_DIR"
    run_overlay "$HOME/does-not-exist"
    assert_success
    assert_output --partial "not present"
}

@test "exits 0 with info when COMPANY_SKILLS_HOME empty" {
    mkdir -p "$SKILLS_DIR" "$HOME/company-skills"
    run_overlay "$HOME/company-skills"
    assert_success
    assert_output --partial "is empty"
}

@test "links private entries into ~/.claude/skills" {
    mkdir -p "$SKILLS_DIR" "$HOME/company-skills/foo" "$HOME/company-skills/bar"
    : > "$HOME/company-skills/foo/SKILL.md"
    : > "$HOME/company-skills/bar/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$SKILLS_DIR/foo" ] && [ "$(readlink "$SKILLS_DIR/foo")" = "$HOME/company-skills/foo" ]
    [ -L "$SKILLS_DIR/bar" ] && [ "$(readlink "$SKILLS_DIR/bar")" = "$HOME/company-skills/bar" ]
}

@test "is idempotent on repeat runs" {
    mkdir -p "$SKILLS_DIR" "$HOME/company-skills/foo"
    : > "$HOME/company-skills/foo/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    before="$(ls -la "$SKILLS_DIR")"

    run_overlay "$HOME/company-skills"
    assert_success
    after="$(ls -la "$SKILLS_DIR")"

    [ "$before" = "$after" ]
}

@test "preserves dotfiles entry on name collision (dotfiles wins)" {
    # Simulate a dotfiles skill named "shared" sitting under
    # ${DOTFILES_ROOT}/claude/skills/shared. The overlay must skip it.
    DOTSKILL="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/shared"
    mkdir -p "$SKILLS_DIR"
    ln -s "$DOTSKILL" "$SKILLS_DIR/shared"

    mkdir -p "$HOME/company-skills/shared"
    : > "$HOME/company-skills/shared/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    assert_output --partial "name conflict"

    # Original dotfiles link preserved.
    [ -L "$SKILLS_DIR/shared" ] && [ "$(readlink "$SKILLS_DIR/shared")" = "$DOTSKILL" ]
}

@test "prunes stale overlay link when private source removed" {
    mkdir -p "$SKILLS_DIR" "$HOME/company-skills/temp"
    : > "$HOME/company-skills/temp/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    [ -L "$SKILLS_DIR/temp" ]

    rm -rf "$HOME/company-skills/temp"
    # Re-create a different skill so the script doesn't early-exit on empty.
    mkdir -p "$HOME/company-skills/keep"
    : > "$HOME/company-skills/keep/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    [ ! -e "$SKILLS_DIR/temp" ]
    [ -L "$SKILLS_DIR/keep" ]
}

@test "skips when no ~/.claude*/skills/ target exists" {
    # No skills dir created. claude/setup.sh has not run yet.
    mkdir -p "$HOME/company-skills/foo"
    : > "$HOME/company-skills/foo/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    assert_output --partial "no ~/.claude"
}
