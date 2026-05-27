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

@test "skips meta directories without SKILL.md (issue #715)" {
    # A marketplace-shaped overlay repo carries metadata dirs alongside
    # real skills. The SKILL.md guard must skip metadata so they do
    # not leak into ~/.claude/skills/.
    mkdir -p "$SKILLS_DIR" \
        "$HOME/company-skills/real-skill" \
        "$HOME/company-skills/.claude-plugin" \
        "$HOME/company-skills/plugins" \
        "$HOME/company-skills/tests" \
        "$HOME/company-skills/docs"
    : > "$HOME/company-skills/real-skill/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$SKILLS_DIR/real-skill" ]
    [ "$(readlink "$SKILLS_DIR/real-skill")" = "$HOME/company-skills/real-skill" ]
    [ ! -e "$SKILLS_DIR/.claude-plugin" ]
    [ ! -e "$SKILLS_DIR/plugins" ]
    [ ! -e "$SKILLS_DIR/tests" ]
    [ ! -e "$SKILLS_DIR/docs" ]
}

@test "meta-only repo treated as empty by _has_entries (PR #717 review)" {
    # Consistency with the overlay loop's SKILL.md guard: if the repo
    # carries ONLY metadata dirs, the early-exit should classify it as
    # empty instead of falling through to the main loop and printing
    # the "overlay applied" success line with all-zero counters.
    mkdir -p "$SKILLS_DIR" \
        "$HOME/company-skills/.claude-plugin" \
        "$HOME/company-skills/plugins" \
        "$HOME/company-skills/tests"

    run_overlay "$HOME/company-skills"
    assert_success
    assert_output --partial "is empty"
}

@test "dual layout — only root-level skill linked, plugins/ ignored (#715)" {
    # Root-level skill alongside a plugins/<plugin>/skills/<skill>
    # nested layout. The overlay must link only the root skill; the
    # plugins/ dir has no SKILL.md and must be skipped.
    mkdir -p "$SKILLS_DIR" \
        "$HOME/company-skills/root-skill" \
        "$HOME/company-skills/plugins/example-suite/skills/nested-skill"
    : > "$HOME/company-skills/root-skill/SKILL.md"
    : > "$HOME/company-skills/plugins/example-suite/skills/nested-skill/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$SKILLS_DIR/root-skill" ]
    [ "$(readlink "$SKILLS_DIR/root-skill")" = "$HOME/company-skills/root-skill" ]
    [ ! -e "$SKILLS_DIR/plugins" ]
}

# ---------------------------------------------------------------------
# issue #791 — 4 CLI 합성 디렉토리 매트릭스
# Claude / Codex / OpenCode / Gemini 모두 entry-level 합성 디렉토리이면
# private overlay 가 4 곳 전부에 동일하게 적용돼야 한다.
# ---------------------------------------------------------------------

@test "links overlay into ~/.codex/skills when present (#791)" {
    CODEX_DIR="$HOME/.codex/skills"
    mkdir -p "$CODEX_DIR" "$HOME/company-skills/foo"
    : > "$HOME/company-skills/foo/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$CODEX_DIR/foo" ]
    [ "$(readlink "$CODEX_DIR/foo")" = "$HOME/company-skills/foo" ]
}

@test "links overlay into ~/.config/opencode/skills when present (#791)" {
    OC_DIR="$HOME/.config/opencode/skills"
    mkdir -p "$OC_DIR" "$HOME/company-skills/bar"
    : > "$HOME/company-skills/bar/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$OC_DIR/bar" ]
    [ "$(readlink "$OC_DIR/bar")" = "$HOME/company-skills/bar" ]
}

@test "links overlay into ~/.gemini/skills when present (#791)" {
    G_DIR="$HOME/.gemini/skills"
    mkdir -p "$G_DIR" "$HOME/company-skills/baz"
    : > "$HOME/company-skills/baz/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    [ -L "$G_DIR/baz" ]
    [ "$(readlink "$G_DIR/baz")" = "$HOME/company-skills/baz" ]
}

@test "skips ~/.gemini/skills when it is still a legacy directory-symlink (#791)" {
    # Pre-migration layout: ~/.gemini/skills is a dir-symlink. The
    # overlay must skip it (-L guard) so setup-skills-ssot.sh has a
    # chance to migrate first. After migration the next overlay run
    # will pick it up — verified separately by the entry-level test.
    mkdir -p "$HOME/.gemini" "$HOME/some-dotfiles-tree/claude/skills"
    ln -s "$HOME/some-dotfiles-tree/claude/skills" "$HOME/.gemini/skills"
    # Sanity: the link must really exist before the run.
    [ -L "$HOME/.gemini/skills" ]

    # No claude target either, so the script should exit informing the
    # user that no target was found.
    mkdir -p "$HOME/company-skills/foo"
    : > "$HOME/company-skills/foo/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success
    # The dir-symlink itself must NOT be touched.
    [ -L "$HOME/.gemini/skills" ]
    # No entry symlink under it (since the script skipped it). The
    # dir-symlink would happily resolve `foo` against the target dir,
    # so check the entry via the symlink path NOT through it.
    [ ! -L "$HOME/.gemini/skills/foo" ]
}

@test "applies overlay to all 4 CLI targets simultaneously (#791)" {
    mkdir -p \
        "$SKILLS_DIR" \
        "$HOME/.codex/skills" \
        "$HOME/.config/opencode/skills" \
        "$HOME/.gemini/skills" \
        "$HOME/company-skills/quad"
    : > "$HOME/company-skills/quad/SKILL.md"

    run_overlay "$HOME/company-skills"
    assert_success

    for tgt in \
        "$SKILLS_DIR/quad" \
        "$HOME/.codex/skills/quad" \
        "$HOME/.config/opencode/skills/quad" \
        "$HOME/.gemini/skills/quad"; do
        [ -L "$tgt" ] || {
            echo "missing overlay entry: $tgt" >&2
            false
        }
        [ "$(readlink "$tgt")" = "$HOME/company-skills/quad" ] || {
            echo "wrong readlink: $tgt -> $(readlink "$tgt")" >&2
            false
        }
    done
}
