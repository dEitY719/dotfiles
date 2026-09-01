#!/usr/bin/env bats
# tests/bats/tools/setup_skills_ssot.bats
# Validate scripts/setup-skills-ssot.sh — focuses on the Codex allowlist
# behaviour that gates the .codex-allowlist file (issue #216).

load '../test_helper'

SETUP_SSOT_SCRIPT="${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"
DIAG_SCRIPT="${DOTFILES_ROOT}/scripts/maintenance/check_codex_skills_budget.py"
UX_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
# Workspace source enumeration is shared with the Claude Code side (#1652).
SKILL_SOURCES_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"

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
        "${FIXTURE_DOTFILES}/shell-common/functions" \
        "${FIXTURE_HOME}/.codex/skills"

    cp "$SETUP_SSOT_SCRIPT" "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
    cp "$UX_LIB_SOURCE" "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$SKILL_SOURCES_LIB_SOURCE" \
        "${FIXTURE_DOTFILES}/shell-common/functions/skill_sources.sh"

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

# ---------------------------------------------------------------------
# issue #1652 — 다중 워크스페이스 루트 스캔 (#1410 F-6 조기 도입)
# dotfiles claude/skills/ 스캔은 그대로 두고(F-2/NF-1), 로컬에 clone 된
# marketplace repo 들(${WORKSPACE_ROOT}/<repo>/skills/<skill>/SKILL.md)을
# 소스 목록에 **추가로** 합류시킨다. fan-out 로직은 손대지 않는다(F-4).
# 워크스페이스 열거 규칙 자체의 SSOT 는 shell-common/functions/skill_sources.sh
# 이고, Claude Code 계정 쪽 커버리지는 claude_compose_workspace_skills.bats.
# ---------------------------------------------------------------------

# Seed a workspace repo under the given root.
# Usage: seed_workspace_skill <workspace_root> <repo> <skill> [<skill>...]
seed_workspace_skill() {
    local root="$1" repo="$2"
    shift 2
    local skill
    for skill in "$@"; do
        mkdir -p "${root}/${repo}/skills/${skill}"
        cat > "${root}/${repo}/skills/${skill}/SKILL.md" <<EOF
---
name: ${skill}
description: workspace stub for ${repo}/${skill}
---
EOF
    done
}

# The default workspace root the script derives from \$HOME (F-1).
default_workspace_root() {
    printf '%s\n' "${FIXTURE_HOME}/para/project/skills"
}

run_setup_with_workspace() {
    WORKSPACE_ROOT="$1" HOME="$FIXTURE_HOME" \
        run bash "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
}

@test "workspace: default root ~/para/project/skills is scanned (#1652 F-1)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta" "epsilon"

    run_setup
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    for s in delta epsilon; do
        [ -L "${oc_dir}/${s}" ]
        [ "$(readlink -f "${oc_dir}/${s}")" \
            = "$(readlink -f "$(default_workspace_root)/packaging-skills/skills/${s}")" ]
    done
}

@test "workspace: dotfiles SSOT keeps being scanned in parallel (#1652 F-2/NF-1)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    # Both sources are represented at once.
    for s in alpha beta gamma; do
        [ -L "${oc_dir}/${s}" ]
        [ "$(readlink -f "${oc_dir}/${s}")" \
            = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/${s}")" ]
    done
    [ -L "${oc_dir}/delta" ]
}

@test "workspace: skills reach every harness including codex (#1652 F-4)" {
    seed_opencode_home
    seed_gemini_home
    seed_hermes_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup
    assert_success

    [ -L "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
    [ -L "${FIXTURE_HOME}/.gemini/skills/delta" ]
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/delta" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/delta" ]
}

@test "workspace: WORKSPACE_ROOT env var overrides the default path (#1652 F-3)" {
    seed_opencode_home
    local custom="${TEST_TEMP_HOME}/custom-workspace"
    seed_workspace_skill "$custom" "other-skills" "zeta"
    # The default location holds a different skill — it must NOT be used.
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup_with_workspace "$custom"
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    [ -L "${oc_dir}/zeta" ]
    [ ! -e "${oc_dir}/delta" ]
}

@test "workspace: absent root is a silent no-op, dotfiles still linked (#1652 Error Case 1)" {
    seed_opencode_home
    [ ! -d "$(default_workspace_root)" ]

    run_setup
    assert_success
    refute_output --partial "No such file"

    for s in alpha beta gamma; do
        [ -L "${FIXTURE_HOME}/.config/opencode/skills/${s}" ]
    done
}

@test "workspace: repo without a skills/ dir is skipped silently (#1652 Error Case 2)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    mkdir -p "${ws}/not-a-skill-repo/docs"
    printf 'readme\n' > "${ws}/not-a-skill-repo/README.md"
    seed_workspace_skill "$ws" "packaging-skills" "delta"

    run_setup
    assert_success

    [ -L "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/not-a-skill-repo" ]
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/docs" ]
}

@test "workspace: skills/ entry without SKILL.md is not a source (#1652 F-1)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "packaging-skills" "delta"
    # A stray directory under skills/ that is not a skill.
    mkdir -p "${ws}/packaging-skills/skills/_shared"
    printf 'notes\n' > "${ws}/packaging-skills/skills/_shared/NOTES.md"

    run_setup
    assert_success

    [ -L "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/_shared" ]
}

@test "workspace: name collision keeps the dotfiles SSOT source (#1652 NF-1)" {
    seed_opencode_home
    # `alpha` already exists in the dotfiles SSOT.
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "alpha"

    run_setup
    assert_success

    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/alpha")" \
        = "$(readlink -f "${FIXTURE_DOTFILES}/claude/skills/alpha")" ]
}

@test "workspace: two repos exposing the same skill — first wins, deterministically (#1652)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    # Mirrors the real `packaging-skills` + `packaging-skills-feat-1`
    # (a git worktree of the same repo) sitting side by side.
    seed_workspace_skill "$ws" "aaa-skills" "delta"
    seed_workspace_skill "$ws" "zzz-skills" "delta"

    run_setup
    assert_success

    # Glob order is sorted, so the alphabetically first repo wins — and
    # the choice must not flip between runs.
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/delta")" \
        = "$(readlink -f "${ws}/aaa-skills/skills/delta")" ]

    run_setup
    assert_success
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/delta")" \
        = "$(readlink -f "${ws}/aaa-skills/skills/delta")" ]
}

@test "workspace: a linked git worktree never shadows its clone (#1652)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "packaging-skills" "delta"
    mkdir -p "${ws}/packaging-skills/.git"
    # A linked worktree of the same repo: `.git` is a file, and the name
    # sorts ahead of the clone under LC_ALL=C ('-' < '/').
    seed_workspace_skill "$ws" "packaging-skills-feat-1" "delta"
    printf 'gitdir: /elsewhere\n' > "${ws}/packaging-skills-feat-1/.git"

    run_setup
    assert_success

    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/delta")" \
        = "$(readlink -f "${ws}/packaging-skills/skills/delta")" ]
}

@test "workspace: WORKSPACE_ROOT of \$HOME is refused as too broad (#1652 safety)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup_with_workspace "$FIXTURE_HOME"
    assert_success

    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
    for s in alpha beta gamma; do
        [ -L "${FIXTURE_HOME}/.config/opencode/skills/${s}" ]
    done
}

@test "workspace: stale entry is pruned when the repo disappears (#1652 NF-3)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "packaging-skills" "delta"

    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/delta" ]

    rm -rf "${ws}/packaging-skills"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
    # dotfiles-sourced entries are untouched.
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/alpha" ]
}

@test "workspace: codex prunes a workspace skill once its repo is gone (#1652 NF-3)" {
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "packaging-skills" "delta"

    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.codex/skills/delta" ]

    rm -rf "${ws}/packaging-skills"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.codex/skills/delta" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/alpha" ]
}

@test "workspace: SKILL.md edits are live through the composed link (#1652 NF-2)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "packaging-skills" "delta"

    run_setup
    assert_success

    # Edit the source in place — no re-install, no re-run.
    printf 'EDITED-IN-WORKSPACE\n' \
        >> "${ws}/packaging-skills/skills/delta/SKILL.md"

    run grep -q 'EDITED-IN-WORKSPACE' \
        "${FIXTURE_HOME}/.config/opencode/skills/delta/SKILL.md"
    assert_success
}

@test "workspace: synthesis stays idempotent with a workspace present (#1652)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

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

@test "workspace: allowlist still gates codex for workspace skills (#1652 F-4)" {
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"
    printf 'alpha\ndelta\n' \
        > "${FIXTURE_DOTFILES}/claude/skills/.codex-allowlist"

    run_setup
    assert_success

    [ -L "${FIXTURE_HOME}/.codex/skills/alpha" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/delta" ]
    [ ! -e "${FIXTURE_HOME}/.codex/skills/beta" ]
}
