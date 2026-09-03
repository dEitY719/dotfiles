#!/usr/bin/env bats
# tests/bats/tools/setup_skills_ssot.bats
# Validate scripts/setup-skills-ssot.sh — the workspace-only fan-out that
# composes locally cloned marketplace repos into every non-Claude harness
# (issue #791 / #1376 / #1652, cut over to workspace-only by #1680).

load '../test_helper'

SETUP_SSOT_SCRIPT="${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"
DIAG_SCRIPT="${DOTFILES_ROOT}/scripts/maintenance/check_codex_skills_budget.py"
UX_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
# Workspace source enumeration is shared with the Claude Code side (#1652).
SKILL_SOURCES_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
# main-worktree canonicalization SSOT (#589) — the script reuses it to widen
# the legacy-link match to the main checkout when run from a worktree (#1732).
DOTFILES_ROOT_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/functions/dotfiles_root.sh"

setup() {
    setup_isolated_home

    # Build a minimal dotfiles fixture under TEST_TEMP_HOME so the
    # script can be invoked without touching the real dotfiles tree.
    FIXTURE_DOTFILES="${TEST_TEMP_HOME}/fixture-dotfiles"
    FIXTURE_HOME="${TEST_TEMP_HOME}/fixture-home"
    # Since #1680 the only skill source is the workspace, so the baseline
    # alpha/beta/gamma fixtures live in a clone under the default root.
    BASE_REPO="${FIXTURE_HOME}/para/project/skills/base-skills"
    mkdir -p \
        "${FIXTURE_DOTFILES}/scripts" \
        "${BASE_REPO}/skills/alpha" \
        "${BASE_REPO}/skills/beta" \
        "${BASE_REPO}/skills/gamma" \
        "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib" \
        "${FIXTURE_DOTFILES}/shell-common/functions" \
        "${FIXTURE_HOME}/.codex/skills"

    cp "$SETUP_SSOT_SCRIPT" "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
    cp "$UX_LIB_SOURCE" "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$SKILL_SOURCES_LIB_SOURCE" \
        "${FIXTURE_DOTFILES}/shell-common/functions/skill_sources.sh"
    cp "$DOTFILES_ROOT_LIB_SOURCE" \
        "${FIXTURE_DOTFILES}/shell-common/functions/dotfiles_root.sh"

    for s in alpha beta gamma; do
        cat > "${BASE_REPO}/skills/${s}/SKILL.md" <<EOF
---
name: ${s}
description: stub description for ${s}
---
EOF
    done

    export FIXTURE_DOTFILES FIXTURE_HOME BASE_REPO
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

# $1 (optional) — the checkout to run the script from; defaults to the
# fixture dotfiles tree. The worktree test (#1732) passes its linked
# worktree instead of re-declaring the invocation.
run_setup() {
    HOME="$FIXTURE_HOME" run bash "${1:-$FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
}

# --- Codex fan-out ---

@test "every workspace skill is symlinked into ~/.codex/skills" {
    run_setup
    assert_success

    for s in alpha beta gamma; do
        local target="${FIXTURE_HOME}/.codex/skills/${s}"
        [ -L "$target" ]
        local resolved
        resolved="$(readlink -f "$target")"
        [ "$resolved" = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
    done
}

# #1680 removed the .codex-allowlist gate along with the dotfiles SSOT that
# held the file. Nothing may reintroduce a silent per-skill filter.
@test "no allowlist gate survives the workspace cutover (#1680)" {
    run grep -n -e "codex-allowlist" -e "codex_skill_is_allowed" \
        "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
    assert_failure
}

# --- Diagnostic script ---

@test "check_codex_skills_budget: reports under-budget and exits 0" {
    run python3 "$DIAG_SCRIPT" \
        --skills-dir "${BASE_REPO}/skills" \
        --budget 1000
    assert_success
    assert_output --regexp 'Skills: +3'
    assert_output --partial "Within budget"
}

@test "check_codex_skills_budget: flags over-budget and exits 1" {
    run python3 "$DIAG_SCRIPT" \
        --skills-dir "${BASE_REPO}/skills" \
        --budget 5
    [ "$status" -eq 1 ]
    assert_output --partial "exceed budget"
    # #1680 retired the .codex-allowlist escape hatch; the advice must not
    # point at a mechanism that no longer exists.
    refute_output --partial ".codex-allowlist"
}

@test "check_codex_skills_budget: no --skills-dir scans the workspace (#1680)" {
    WORKSPACE_ROOT="${FIXTURE_HOME}/para/project/skills" \
        run python3 "$DIAG_SCRIPT" --budget 1000
    assert_success
    assert_output --regexp 'Skills: +3'
    assert_output --partial "para/project/skills"
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
        [ "$(readlink -f "${oc_dir}/${s}")" = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
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
        [ "$(readlink -f "${g_dir}/${s}")" = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
    done
}

@test "opencode: legacy dir-symlink migrates to entry-level synthesis (#791)" {
    seed_opencode_home
    # Pre-state: the legacy directory symlink into the dotfiles SSOT that
    # #1680 deleted — i.e. a dangling link, which holds no user data.
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
    # Dangling — the #1680 cutover removed the target (see opencode twin).
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
    rm -rf "${BASE_REPO}/skills/beta"

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
        [ "$(readlink -f "${h_dir}/${s}")" = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
    done

    # skills/ 루트에는 entry symlink 가 직접 생기지 않는다.
    [ ! -L "${FIXTURE_HOME}/.hermes/skills/alpha" ]
}

@test "hermes: legacy dir-symlink migrates to entry-level synthesis (#1376)" {
    seed_hermes_home
    mkdir -p "${FIXTURE_HOME}/.hermes/skills"
    # Dangling — the #1680 cutover removed the target (see opencode twin).
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
    rm -rf "${BASE_REPO}/skills/beta"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.hermes/skills/dotfiles/beta" ]
    # Other skills still present; sibling hub dirs untouched.
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/alpha" ]
    [ -L "${FIXTURE_HOME}/.hermes/skills/dotfiles/gamma" ]
}

# ---------------------------------------------------------------------
# issue #1652 / #1680 — 워크스페이스 루트 스캔이 유일한 소스
# 로컬에 clone 된 marketplace repo 들
# (${WORKSPACE_ROOT}/<repo>/skills/<skill>/SKILL.md) 이 소스 전부다.
# 열거 규칙 자체의 SSOT 는 shell-common/functions/skill_sources.sh 이고,
# Claude Code 계정 쪽 커버리지는 claude_compose_workspace_skills.bats.
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

@test "workspace: every repo under the root is scanned (#1652 F-2)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    # Both workspace repos are represented at once.
    for s in alpha beta gamma; do
        [ -L "${oc_dir}/${s}" ]
        [ "$(readlink -f "${oc_dir}/${s}")" \
            = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
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

# With the dotfiles SSOT gone (#1680) an absent workspace means there is
# nothing to link. The script must say so and stop — NOT fall through to the
# fan-out, whose stale-prune would then wipe every entry already composed.
@test "workspace: absent root skips the fan-out instead of pruning it (#1680)" {
    seed_opencode_home
    # Compose once from a real workspace, then take the workspace away.
    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.config/opencode/skills/alpha" ]

    rm -rf "${FIXTURE_HOME}/para"
    [ ! -d "$(default_workspace_root)" ]

    run_setup
    assert_success
    refute_output --partial "No such file"
    assert_output --partial "skill 소스가 없습니다"

    # Previously composed entries survive untouched.
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

@test "workspace: name collision — bare name to first repo, others get qualified entries (#1652 NF-1, #1746)" {
    seed_opencode_home
    # `alpha` already comes from base-skills, which sorts first.
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "alpha"

    run_setup
    assert_success

    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/alpha")" \
        = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
    # The loser is no longer dropped — it is composed under a repo-qualified
    # entry name so both skills stay reachable (#1746).
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/packaging-skills__alpha")" \
        = "$(readlink -f "$(default_workspace_root)/packaging-skills/skills/alpha")" ]
}

@test "workspace: two repos exposing the same skill — both coexist, bare name to first repo (#1652, #1746)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    # Mirrors the real `packaging-skills` + `packaging-skills-feat-1`
    # (a git worktree of the same repo) sitting side by side.
    seed_workspace_skill "$ws" "aaa-skills" "delta"
    seed_workspace_skill "$ws" "zzz-skills" "delta"

    run_setup
    assert_success

    # Glob order is sorted, so the alphabetically first repo keeps the bare
    # name — and the choice must not flip between runs.
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/delta")" \
        = "$(readlink -f "${ws}/aaa-skills/skills/delta")" ]
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/zzz-skills__delta")" \
        = "$(readlink -f "${ws}/zzz-skills/skills/delta")" ]

    run_setup
    assert_success
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/delta")" \
        = "$(readlink -f "${ws}/aaa-skills/skills/delta")" ]
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/zzz-skills__delta")" \
        = "$(readlink -f "${ws}/zzz-skills/skills/delta")" ]
}

# The exact shape #1746 reports: three unrelated repos each shipping `create`.
@test "workspace: a three-way name collision exposes all three skills (#1746)" {
    seed_opencode_home
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "gh-issue-skills" "create"
    seed_workspace_skill "$ws" "gh-pr-skills" "create"
    seed_workspace_skill "$ws" "packaging-skills" "create"

    run_setup
    assert_success

    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/create")" \
        = "$(readlink -f "${ws}/gh-issue-skills/skills/create")" ]
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/gh-pr-skills__create")" \
        = "$(readlink -f "${ws}/gh-pr-skills/skills/create")" ]
    [ "$(readlink -f "${FIXTURE_HOME}/.config/opencode/skills/packaging-skills__create")" \
        = "$(readlink -f "${ws}/packaging-skills/skills/create")" ]
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
    # The worktree is filtered out upstream, so there is no real collision to
    # qualify — no `<worktree>__delta` entry may appear (#1746).
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/packaging-skills-feat-1__delta" ]
}

@test "workspace: WORKSPACE_ROOT of \$HOME is refused as too broad (#1652 safety)" {
    seed_opencode_home
    seed_workspace_skill "$(default_workspace_root)" "packaging-skills" "delta"

    run_setup_with_workspace "$FIXTURE_HOME"
    assert_success

    # Refused root == no sources == the #1680 skip guard, not a wipe.
    assert_output --partial "skill 소스가 없습니다"
    [ ! -e "${FIXTURE_HOME}/.config/opencode/skills/delta" ]
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
    # The surviving repo's entries are untouched.
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

# The qualified name has to round-trip through skill_source_path_for, or
# codex's stale prune would delete it on the very next run (#1746).
@test "workspace: codex keeps a qualified entry, then prunes it with its repo (#1746)" {
    local ws
    ws="$(default_workspace_root)"
    seed_workspace_skill "$ws" "aaa-skills" "delta"
    seed_workspace_skill "$ws" "zzz-skills" "delta"

    run_setup
    assert_success
    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.codex/skills/zzz-skills__delta" ]

    rm -rf "${ws}/zzz-skills"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.codex/skills/zzz-skills__delta" ]
    [ -L "${FIXTURE_HOME}/.codex/skills/delta" ]
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


# ---------------------------------------------------------------------
# issue #1732 — entry-level stale symlink cleanup
# PR #1729 taught the *directory-level* migration to recognize a broken
# link into the deleted `dotfiles/claude/skills` SSOT (#1680), but the
# *entry-level* loops kept classifying such a link as user data. Two
# distinct symptoms follow: an entry whose name still has a live source
# is never replaced (the skill stays hidden), and an entry whose name no
# longer exists anywhere is never pruned (dead links accumulate).
# ---------------------------------------------------------------------

# Seed the composed dir, then inject the legacy links the #1680 cutover
# stranded there. Two shapes: `alpha` collides with a live source (hidden
# skill), `legacy-orphan` has no source at all (dead link).
seed_legacy_entries() {
    local dir="$1"
    rm -f "${dir}/alpha"
    ln -s "${FIXTURE_DOTFILES}/claude/skills/alpha/" "${dir}/alpha"
    ln -s "${FIXTURE_DOTFILES}/claude/skills/legacy-orphan/" "${dir}/legacy-orphan"
}

@test "gemini: legacy entry shadowing a live source is relinked (#1732)" {
    seed_gemini_home
    run_setup
    assert_success

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    seed_legacy_entries "$g_dir"

    run_setup
    assert_success

    [ -L "${g_dir}/alpha" ]
    [ -e "${g_dir}/alpha" ]
    [ "$(readlink -f "${g_dir}/alpha")" = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
}

@test "gemini: legacy entry with no live source is pruned (#1732)" {
    seed_gemini_home
    run_setup
    assert_success

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    seed_legacy_entries "$g_dir"

    run_setup
    assert_success

    [ ! -L "${g_dir}/legacy-orphan" ]
}

@test "opencode: legacy entries are cleaned across every harness (#1732)" {
    seed_opencode_home
    seed_hermes_home
    run_setup
    assert_success

    local oc_dir="${FIXTURE_HOME}/.config/opencode/skills"
    local h_dir="${FIXTURE_HOME}/.hermes/skills/dotfiles"
    seed_legacy_entries "$oc_dir"
    seed_legacy_entries "$h_dir"

    run_setup
    assert_success

    local d
    for d in "$oc_dir" "$h_dir"; do
        [ -e "${d}/alpha" ]
        [ "$(readlink -f "${d}/alpha")" = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
        [ ! -L "${d}/legacy-orphan" ]
    done
}

@test "codex: legacy entries are relinked and pruned (#1732)" {
    run_setup
    assert_success

    local c_dir="${FIXTURE_HOME}/.codex/skills"
    seed_legacy_entries "$c_dir"

    run_setup
    assert_success

    [ -e "${c_dir}/alpha" ]
    [ "$(readlink -f "${c_dir}/alpha")" = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
    [ ! -L "${c_dir}/legacy-orphan" ]
}

# The counter-case that keeps the fix honest: a broken link pointing
# somewhere that is NOT the deleted SSOT (a temporarily unmounted user
# mount, say) still holds recoverable user intent — preserve it.
@test "gemini: broken entry outside the legacy SSOT is preserved (#1732)" {
    seed_gemini_home
    run_setup
    assert_success

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    rm -f "${g_dir}/beta"
    ln -s "${TEST_TEMP_HOME}/unmounted/skills/beta" "${g_dir}/beta"

    run_setup
    assert_success
    assert_output --partial "[gemini] 사용자 symlink 보존"

    [ -L "${g_dir}/beta" ]
    [ "$(readlink "${g_dir}/beta")" = "${TEST_TEMP_HOME}/unmounted/skills/beta" ]
}

# A worktree checkout resolves DOTFILES_ROOT to the worktree path, while
# the stranded links were written against the main checkout. Matching on
# DOTFILES_ROOT alone therefore misses every one of them — exactly the
# state a re-run from a worktree has to be able to repair.
@test "gemini: legacy entries are cleaned when run from a git worktree (#1732)" {
    seed_gemini_home

    git -C "$FIXTURE_DOTFILES" init -q
    git -C "$FIXTURE_DOTFILES" config user.email t@example.com
    git -C "$FIXTURE_DOTFILES" config user.name t
    git -C "$FIXTURE_DOTFILES" add -A
    git -C "$FIXTURE_DOTFILES" commit -qm init
    local wt="${TEST_TEMP_HOME}/wt-dotfiles"
    git -C "$FIXTURE_DOTFILES" worktree add -q -b wt/test "$wt"

    run_setup
    assert_success
    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    seed_legacy_entries "$g_dir"

    # Run from the worktree — DOTFILES_ROOT is now "$wt", but the links
    # still name "$FIXTURE_DOTFILES".
    run_setup "$wt"
    assert_success

    [ -e "${g_dir}/alpha" ]
    [ "$(readlink -f "${g_dir}/alpha")" = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
    [ ! -L "${g_dir}/legacy-orphan" ]
}

# 레거시 링크가 상대 경로로 적혀 있어도 같은 판정을 받아야 한다 (#1732,
# agy FOLLOW-UP). 스크립트 자신은 항상 절대 경로로 링크를 만들지만, 수동/
# 외부 도구가 만든 상대 경로 링크는 절대 경로 prefix 매칭을 그냥 빠져나간다.
@test "gemini: relative-path legacy entry is cleaned too (#1732)" {
    seed_gemini_home
    run_setup
    assert_success

    local g_dir="${FIXTURE_HOME}/.gemini/skills"
    local rel
    rel="$(realpath -m --relative-to="$g_dir" "${FIXTURE_DOTFILES}/claude/skills")"
    rm -f "${g_dir}/alpha"
    ln -s "${rel}/alpha" "${g_dir}/alpha"
    ln -s "${rel}/legacy-orphan" "${g_dir}/legacy-orphan"

    run_setup
    assert_success

    [ -e "${g_dir}/alpha" ]
    [ "$(readlink -f "${g_dir}/alpha")" = "$(readlink -f "${BASE_REPO}/skills/alpha")" ]
    [ ! -L "${g_dir}/legacy-orphan" ]
}

# ---------------------------------------------------------------------
# issue #1731 — Antigravity CLI (agy) 전용 합성 (근거: agy/AGENTS.md)
# ---------------------------------------------------------------------

# agy 상태 디렉토리. 설치 판별은 이 디렉토리 또는 PATH 상의 `agy` 바이너리다.
seed_agy_home() {
    mkdir -p "${FIXTURE_HOME}/.gemini/antigravity-cli"
}

# agy 가 설치되지 않은 환경을 재현한다 — 상태 디렉토리를 안 만드는 것만으로는
# 부족하고, 실행 PC 의 PATH 에 놓인 실제 `agy` 바이너리도 가려야 한다.
run_setup_without_agy() {
    HOME="$FIXTURE_HOME" PATH="/usr/bin:/bin" \
        run bash "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
}

@test "agy: composes into its own ~/.gemini/config/skills root (#1731)" {
    seed_agy_home

    run_setup
    assert_success

    local a_dir="${FIXTURE_HOME}/.gemini/config/skills"
    [ -d "$a_dir" ] && [ ! -L "$a_dir" ]
    for s in alpha beta gamma; do
        [ -L "${a_dir}/${s}" ]
        [ "$(readlink -f "${a_dir}/${s}")" = "$(readlink -f "${BASE_REPO}/skills/${s}")" ]
    done

    # agy 루트는 Gemini 루트를 대체하지 않고 **추가**된다: seed_agy_home 이
    # 만든 ~/.gemini 때문에 Gemini 블록도 함께 돌아 두 경로가 모두 채워진다
    # (PR #1734 codex FOLLOW-UP — 예전 테스트명은 반대를 주장했다).
    [ -L "${FIXTURE_HOME}/.gemini/skills/alpha" ]
}

@test "agy: neither state dir nor binary skips the fan-out (#1731)" {
    # ~/.gemini 는 있지만 agy 는 설치되지 않은 순정 Gemini 환경.
    seed_gemini_home

    run_setup_without_agy
    assert_success
    [ ! -e "${FIXTURE_HOME}/.gemini/config/skills" ]
    # Gemini 자신의 합성은 영향을 받지 않는다.
    [ -L "${FIXTURE_HOME}/.gemini/skills/alpha" ]
}

@test "agy: binary on PATH alone triggers the fan-out (#1731, agy FOLLOW-UP)" {
    # 바이너리는 설치됐지만 아직 한 번도 실행하지 않아 상태 디렉토리가 없는 환경.
    seed_gemini_home
    mkdir -p "${TEST_TEMP_HOME}/fake-bin"
    printf '#!/bin/sh\nexit 0\n' > "${TEST_TEMP_HOME}/fake-bin/agy"
    chmod +x "${TEST_TEMP_HOME}/fake-bin/agy"

    HOME="$FIXTURE_HOME" PATH="${TEST_TEMP_HOME}/fake-bin:${PATH}" \
        run bash "${FIXTURE_DOTFILES}/scripts/setup-skills-ssot.sh"
    assert_success

    [ ! -d "${FIXTURE_HOME}/.gemini/antigravity-cli" ]
    [ -L "${FIXTURE_HOME}/.gemini/config/skills/alpha" ]
}

@test "agy: stale entry whose source vanished gets pruned (#1731)" {
    seed_agy_home

    run_setup
    assert_success
    [ -L "${FIXTURE_HOME}/.gemini/config/skills/beta" ]

    rm -rf "${BASE_REPO}/skills/beta"

    run_setup
    assert_success
    [ ! -e "${FIXTURE_HOME}/.gemini/config/skills/beta" ]
    [ -L "${FIXTURE_HOME}/.gemini/config/skills/alpha" ]
}

@test "agy: user symlink to non-SSOT location is preserved + warned (#1731)" {
    seed_agy_home
    mkdir -p "${FIXTURE_HOME}/.gemini/config" "${TEST_TEMP_HOME}/elsewhere/agy-skills"
    ln -s "${TEST_TEMP_HOME}/elsewhere/agy-skills" \
        "${FIXTURE_HOME}/.gemini/config/skills"

    run_setup
    assert_success
    assert_output --partial "[agy] 사용자 symlink"

    [ -L "${FIXTURE_HOME}/.gemini/config/skills" ]
    [ "$(readlink "${FIXTURE_HOME}/.gemini/config/skills")" = "${TEST_TEMP_HOME}/elsewhere/agy-skills" ]
}
