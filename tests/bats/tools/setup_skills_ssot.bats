#!/usr/bin/env bats
# tests/bats/tools/setup_skills_ssot.bats
# Validate scripts/setup-skills-ssot.sh — focuses on the Codex allowlist
# behaviour that gates the .codex-allowlist file (issue #216).

load '../test_helper'

SETUP_SSOT_SCRIPT="${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"
DIAG_SCRIPT="${DOTFILES_ROOT}/scripts/maintenance/check_codex_skills_budget.py"
UX_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"

setup() {
    setup_isolated_home

    # Build a minimal dotfiles fixture under TEST_TEMP_HOME so the
    # script can be invoked without touching the real dotfiles tree.
    FIXTURE_DOTFILES="${TEST_TEMP_HOME}/fixture-dotfiles"
    FIXTURE_HOME="${TEST_TEMP_HOME}/fixture-home"
    mkdir -p \
        "${FIXTURE_DOTFILES}/scripts" \
        "${FIXTURE_DOTFILES}/claude/skills/alpha" \
        "${FIXTURE_DOTFILES}/claude/skills/beta" \
        "${FIXTURE_DOTFILES}/claude/skills/gamma" \
        "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib" \
        "${FIXTURE_HOME}/.codex/skills"

    cp "$SETUP_SSOT_SCRIPT" "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
    cp "$UX_LIB_SOURCE" "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib/ux_lib.sh"

    for s in alpha beta gamma; do
        cat > "${FIXTURE_DOTFILES}/claude/skills/${s}/SKILL.md" <<EOF
---
name: ${s}
description: stub description for ${s}
---
EOF
    done

    export FIXTURE_DOTFILES FIXTURE_HOME
}

# Provision the opencode + gemini config dirs so the script's CLI-presence
# guards (`[ -d ~/.config/opencode ]` / `[ -d ~/.gemini ]`) light up. Each
# test that exercises the entry-level synthesis calls this helper to set
# the initial layout (real-dir, dir-symlink, or absent skills/ subdir).
seed_opencode_home() {
    mkdir -p "${FIXTURE_HOME}/.config/opencode"
}
seed_gemini_home() {
    mkdir -p "${FIXTURE_HOME}/.gemini"
}

teardown() {
    teardown_isolated_home
}

run_setup() {
    HOME="$FIXTURE_HOME" run bash "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
}

# --- Allowlist behaviour ---

@test "no allowlist file: every SSOT skill is symlinked into ~/.codex/skills" {
    run_setup
    assert_success

    for s in alpha beta gamma; do
        local target="${FIXTURE_HOME}/.codex/skills/${s}"
        [ -L "$target" ]
        local resolved
        resolved="$(readlink -f "$target")"
        [ "$resolved" = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/${s}")" ]
    done
}

@test "allowlist with two entries: only listed skills are linked" {
    cat > "${FIXTURE_DOTFILES}/claude/skills/.codex-allowlist" <<EOF
# Pinned codex skills
alpha
gamma
EOF

    run_setup
    assert_success
    assert_output --partial "allowlist 적용: 2개 skill"

    [ -L "${FIXTURE_HOME}/.codex/skills/alpha" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/gamma" ]
    [ ! -e "${FIXTURE_HOME}/.codex/skills/beta" ]
}

@test "allowlist prunes a previously linked skill that is no longer allowed" {
    # First sync without an allowlist — beta gets linked.
    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.codex/skills/beta" ]

    # Add an allowlist that excludes beta and re-run.
    printf 'alpha\ngamma\n' \
        > "${FIXTURE_DOTFILES}/claude/skills/.codex-allowlist"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.codex/skills/beta" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/alpha" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/gamma" ]
}

@test "allowlist with only comments behaves as if missing (link all)" {
    cat > "${FIXTURE_DOTFILES}/claude/skills/.codex-allowlist" <<EOF
# everything is commented out
# beta
EOF

    run_setup
    assert_success
    refute_output --partial "allowlist 적용"

    for s in alpha beta gamma; do
        [ -L "${FIXTURE_HOME}/.codex/skills/${s}" ]
    done
}

# --- Diagnostic script ---

@test "check_codex_skills_budget: reports under-budget and exits 0" {
    run python3 "$DIAG_SCRIPT" \
        --skills-dir "${FIXTURE_DOTFILES}/claude/skills" \
        --budget 1000
    assert_success
    assert_output --partial "Skills:     3"
    assert_output --partial "Within budget"
}

@test "check_codex_skills_budget: flags over-budget and exits 1" {
    run python3 "$DIAG_SCRIPT" \
        --skills-dir "${FIXTURE_DOTFILES}/claude/skills" \
        --budget 5
    [ "$status" -eq 1 ]
    assert_output --partial "exceed budget"
    assert_output --partial ".codex-allowlist"
}

# ---------------------------------------------------------------------
# issue #791 — OpenCode / Gemini entry-level 합성
# 이전 디렉토리-단위 symlink 를 entry-level 합성 디렉토리로 변환.
# ---------------------------------------------------------------------

@test "opencode: fresh install creates entry-level synthesis directory (#791)" {
    seed_opencode_home

    run_setup
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    [ -d "$oc_dir" ] && [ ! -L "$oc_dir" ]
    for s in alpha beta gamma; do
        [ -L "${oc_dir}/${s}" ]
        [ "$(readlink -f "${oc_dir}/${s}")" = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/${s}")" ]
    done
}

@test "gemini: fresh install creates entry-level synthesis directory (#791)" {
    seed_gemini_home

    run_setup
    assert_success

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    [ -d "$g_dir" ] && [ ! -L "$g_dir" ]
    for s in alpha beta gamma; do
        [ -L "${g_dir}/${s}" ]
        [ "$(readlink -f "${g_dir}/${s}")" = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/${s}")" ]
    done
}

@test "opencode: legacy dir-symlink migrates to entry-level synthesis (#791)" {
    seed_opencode_home
    # Pre-state: legacy directory symlink → SSOT.
    ln -s "${FIXTURE_DOTFILES}/claude/skills" \
        "${FIXTURE_HOME}/.config/opencode/skills"
    [ -L "${FIXTURE_HOME}/.config/opencode/skills" ]

    run_setup
    assert_success
    assert_output --partial "[opencode] legacy dir-symlink"

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    [ ! -L "$oc_dir" ]
    [ -d "$oc_dir" ]
    for s in alpha beta gamma; do
        [ -L "${oc_dir}/${s}" ]
    done
}

@test "gemini: legacy dir-symlink migrates to entry-level synthesis (#791)" {
    seed_gemini_home
    ln -s "${FIXTURE_DOTFILES}/claude/skills" "${FIXTURE_HOME}/.gemini/skills"
    [ -L "${FIXTURE_HOME}/.gemini/skills" ]

    run_setup
    assert_success
    assert_output --partial "[gemini] legacy dir-symlink"

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    [ ! -L "$g_dir" ]
    [ -d "$g_dir" ]
    for s in alpha beta gamma; do
        [ -L "${g_dir}/${s}" ]
    done
}

@test "opencode: synthesis is idempotent on re-run (#791)" {
    seed_opencode_home

    run_setup
    assert_success
    local before
    before="$(ls -la "${FIXTURE_HOME}/.config/opencode/skills")"

    run_setup
    assert_success
    local after
    after="$(ls -la "${FIXTURE_HOME}/.config/opencode/skills")"

    [ "$before" = "$after" ]
}

@test "gemini: user symlink to non-SSOT location is preserved + warned (#791)" {
    seed_gemini_home
    # User-managed symlink pointing somewhere other than the SSOT.
    mkdir -p "${TEST_TEMP_HOME}/elsewhere/skills"
    ln -s "${TEST_TEMP_HOME}/elsewhere/skills" "${FIXTURE_HOME}/.gemini/skills"

    run_setup
    assert_success
    assert_output --partial "[gemini] 사용자 symlink"

    # The user's symlink must NOT have been clobbered.
    [ -L "${FIXTURE_HOME}/.gemini/skills" ]
    [ "$(readlink "${FIXTURE_HOME}/.gemini/skills")" = "${TEST_TEMP_HOME}/elsewhere/skills" ]
}

@test "opencode: stale entry whose source vanished gets pruned (#791)" {
    seed_opencode_home

    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/beta" ]

    # Remove `beta` from the SSOT, then re-run. The stale entry under
    # opencode must be cleaned up.
    rm -rf "${FIXTURE_DOTFILES}/claude/skills/beta"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/beta" ]
    # Other skills still present.
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/alpha" ]
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/gamma" ]
}
