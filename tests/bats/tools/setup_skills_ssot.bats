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
# Hermes (#1376) composes into the dedicated `skills/dotfiles` subdirectory
# rather than the `skills/` root, because `~/.hermes/skills/` is an actively
# managed hub (hub metadata + category dirs) owned by Hermes itself.
seed_hermes_home() {
    mkdir -p "${FIXTURE_HOME}/.hermes"
}
# Portable per-file `stat` snapshot (GNU `-c` first, BSD `-f` fallback —
# same try-GNU-then-BSD idiom as shell-common/functions/file_cleanup.sh).
# A combined `xargs stat -c ...` call fails outright on macOS/BSD stat,
# and with its stderr suppressed both the before/after snapshots would
# collapse to the same empty string — silently defeating the comparison
# instead of failing loudly (agy review, PR #1383).
_stat_snapshot() {
    local f
    while IFS= read -r -d '' f; do
        stat -c '%n %s %Y %a' "$f" 2>/dev/null || stat -f '%N %z %m %OLp' "$f" 2>/dev/null
    done
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

@test "hermes: config dir absent is a non-fatal warn + skip (#1376)" {
    # No seed_hermes_home — ~/.hermes does not exist.
    run_setup
    assert_success
    assert_output --partial "Hermes 설정 디렉토리가 없습니다"
    [ ! -e "${FIXTURE_HOME}/.hermes" ]
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

# ---------------------------------------------------------------------
# issue #1376 — Hermes entry-level 합성
# 다른 4개 CLI 와 달리 Hermes 는 skills/ 루트가 아니라 전용 네임스페이스
# 서브디렉토리(skills/dotfiles/)에서 합성한다 — 루트는 Hermes 자체
# hub/curator 메타데이터와 카테고리 디렉토리가 소유하기 때문 (NF-1).
# ---------------------------------------------------------------------

@test "hermes: fresh install creates entry-level synthesis subdirectory (#1376)" {
    seed_hermes_home

    run_setup
    assert_success

    local h_dir="${FIXTURE_HOME}/.hermes/skills/dotfiles"
    [ -d "$h_dir" ] && [ ! -L "$h_dir" ]
    for s in alpha beta gamma; do
        [ -L "${h_dir}/${s}" ]
        [ "$(readlink -f "${h_dir}/${s}")" = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/${s}")" ]
    done

    # skills/ 루트에는 entry symlink 가 직접 생기지 않는다.
    [ ! -L "${FIXTURE_HOME}/.hermes/skills/alpha" ]
}

@test "hermes: legacy dir-symlink migrates to entry-level synthesis (#1376)" {
    seed_hermes_home
    mkdir -p "${FIXTURE_HOME}/.hermes/skills"
    ln -s "${FIXTURE_DOTFILES}/claude/skills" \
        "${FIXTURE_HOME}/.hermes/skills/dotfiles"
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles" ]

    run_setup
    assert_success
    assert_output --partial "[hermes] legacy dir-symlink"

    local h_dir="${FIXTURE_HOME}/.hermes/skills/dotfiles"
    [ ! -L "$h_dir" ]
    [ -d "$h_dir" ]
    for s in alpha beta gamma; do
        [ -L "${h_dir}/${s}" ]
    done
}

@test "hermes: synthesis is idempotent on re-run (#1376)" {
    seed_hermes_home

    run_setup
    assert_success
    local before
    before="$(ls -la "${FIXTURE_HOME}/.hermes/skills/dotfiles")"

    run_setup
    assert_success
    local after
    after="$(ls -la "${FIXTURE_HOME}/.hermes/skills/dotfiles")"

    [ "$before" = "$after" ]
}

@test "hermes: user symlink to non-SSOT location is preserved + warned (#1376)" {
    seed_hermes_home
    mkdir -p "${FIXTURE_HOME}/.hermes/skills"
    mkdir -p "${TEST_TEMP_HOME}/elsewhere-hermes/skills"
    ln -s "${TEST_TEMP_HOME}/elsewhere-hermes/skills" \
        "${FIXTURE_HOME}/.hermes/skills/dotfiles"

    run_setup
    assert_success
    assert_output --partial "[hermes] 사용자 symlink"

    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles" ]
    [ "$(readlink "${FIXTURE_HOME}/.hermes/skills/dotfiles")" \
        = "${TEST_TEMP_HOME}/elsewhere-hermes/skills" ]
}

@test "hermes: hub metadata and category dirs are left untouched (#1376 NF-1)" {
    seed_hermes_home
    local hs="${FIXTURE_HOME}/.hermes/skills"
    mkdir -p "${hs}/.hub" "${hs}/github/gh-helper" "${hs}/productivity"
    printf 'gh-helper:deadbeef\n' > "${hs}/.bundled_manifest"
    printf '{"last_run":0}\n' > "${hs}/.curator_state"
    printf '{"gh-helper":3}\n' > "${hs}/.usage.json"
    printf 'audit\n' > "${hs}/.hub/audit.log"
    printf 'stub\n' > "${hs}/github/gh-helper/SKILL.md"

    # Snapshot content + mtime of every Hermes-owned path.
    local before_listing before_hashes
    before_listing="$(cd "$hs" && ls -A | LC_ALL=C sort)"
    before_hashes="$(cd "$hs" && find . -path ./dotfiles -prune -o -type f -print0 \
        | LC_ALL=C sort -z | _stat_snapshot)"

    run_setup
    assert_success

    local after_hashes
    after_hashes="$(cd "$hs" && find . -path ./dotfiles -prune -o -type f -print0 \
        | LC_ALL=C sort -z | _stat_snapshot)"
    [ "$before_hashes" = "$after_hashes" ]

    # Hermes-owned directories survive intact.
    [ -d "${hs}/.hub" ]
    [ -d "${hs}/github/gh-helper" ]
    [ -d "${hs}/productivity" ]
    [ ! -L "${hs}/github" ]
    [ ! -L "${hs}/productivity" ]

    # Exactly one new top-level entry was created: dotfiles/.
    local after_listing
    after_listing="$(cd "$hs" && ls -A | LC_ALL=C sort)"
    local added
    added="$(comm -13 <(printf '%s\n' "$before_listing") <(printf '%s\n' "$after_listing"))"
    [ "$added" = "dotfiles" ]

    # And the synthesis really happened inside it.
    for s in alpha beta gamma; do
        [ -L "${hs}/dotfiles/${s}" ]
    done
}

@test "hermes: stale entry whose source vanished gets pruned (#1376)" {
    seed_hermes_home

    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/beta" ]

    # Remove `beta` from the SSOT, then re-run. link_skills_compose's
    # stale-entry pruning must also fire on the nested target dir
    # (~/.hermes/skills/dotfiles), not just root-level compose targets
    # like opencode/gemini (codex review, PR #1383).
    rm -rf "${FIXTURE_DOTFILES}/claude/skills/beta"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.hermes/skills/dotfiles/beta" ]
    # Other skills still present; sibling hub dirs untouched.
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/alpha" ]
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/gamma" ]
}
