#!/usr/bin/env bats
# tests/bats/tools/sync_gemini_skills_namespace.bats
# Validate scripts/sync-gemini-skills-namespace.sh (issue #1784)

load '../test_helper'

SYNC_SCRIPT="${DOTFILES_ROOT}/scripts/sync-gemini-skills-namespace.sh"
UX_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
SKILL_SOURCES_LIB_SOURCE="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"

setup() {
    setup_isolated_home

    FIXTURE_DOTFILES="${TEST_TEMP_HOME}/fixture-dotfiles"
    FIXTURE_HOME="${TEST_TEMP_HOME}/fixture-home"
    WORKSPACE="${FIXTURE_HOME}/para/project/skills"

    mkdir -p \
        "${FIXTURE_DOTFILES}/scripts" \
        "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib" \
        "${FIXTURE_DOTFILES}/shell-common/functions" \
        "${FIXTURE_HOME}/.gemini/config/skills" \
        "${FIXTURE_HOME}/.gemini/skills"

    cp "$SYNC_SCRIPT" "${FIXTURE_DOTFILES}/scripts/sync-gemini-skills-namespace.sh"
    cp "$UX_LIB_SOURCE" "${FIXTURE_DOTFILES}/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$SKILL_SOURCES_LIB_SOURCE" "${FIXTURE_DOTFILES}/shell-common/functions/skill_sources.sh"

    # Create dummy skill repos (mindepth 4 maxdepth 4: <root>/<repo>/skills/<skill>/SKILL.md)
    mkdir -p \
        "${WORKSPACE}/gh-flow-skills/skills/issue" \
        "${WORKSPACE}/gh-flow-skills/skills/autopilot" \
        "${WORKSPACE}/gh-issue-skills/skills/make-issue" \
        "${WORKSPACE}/authoring-skills/skills/skill-check"

    cat > "${WORKSPACE}/gh-flow-skills/skills/issue/SKILL.md" <<'SKILLEOF'
---
name: issue
description: issue skill
---
SKILLEOF
    cat > "${WORKSPACE}/gh-flow-skills/skills/autopilot/SKILL.md" <<'SKILLEOF'
---
name: autopilot
description: autopilot skill
---
SKILLEOF
    cat > "${WORKSPACE}/gh-issue-skills/skills/make-issue/SKILL.md" <<'SKILLEOF'
---
name: make-issue
description: make-issue skill
---
SKILLEOF
    cat > "${WORKSPACE}/authoring-skills/skills/skill-check/SKILL.md" <<'SKILLEOF'
---
name: skill-check
description: skill check skill
---
SKILLEOF

    export FIXTURE_DOTFILES FIXTURE_HOME WORKSPACE
}

teardown() {
    teardown_isolated_home
}

run_sync() {
    HOME="$FIXTURE_HOME" WORKSPACE_ROOT="$WORKSPACE" \
        run bash "${FIXTURE_DOTFILES}/scripts/sync-gemini-skills-namespace.sh" "$@"
}

@test "sync-gemini-skills-namespace: creates namespaced symlinks in agy dir (#1784, #1787)" {
    run_sync
    assert_success

    local agy_dir="${FIXTURE_HOME}/.gemini/config/skills"
    local gem_dir="${FIXTURE_HOME}/.gemini/skills"

    [ -L "${agy_dir}/gh-flow:issue" ]
    [ "$(readlink -f "${agy_dir}/gh-flow:issue")" = "$(readlink -f "${WORKSPACE}/gh-flow-skills/skills/issue")" ]
    [ -L "${agy_dir}/gh-flow:autopilot" ]
    [ "$(readlink -f "${agy_dir}/gh-flow:autopilot")" = "$(readlink -f "${WORKSPACE}/gh-flow-skills/skills/autopilot")" ]
    [ -L "${agy_dir}/gh-issue:make-issue" ]
    [ "$(readlink -f "${agy_dir}/gh-issue:make-issue")" = "$(readlink -f "${WORKSPACE}/gh-issue-skills/skills/make-issue")" ]
    [ -L "${agy_dir}/authoring:skill-check" ]
    [ "$(readlink -f "${agy_dir}/authoring:skill-check")" = "$(readlink -f "${WORKSPACE}/authoring-skills/skills/skill-check")" ]

    # 순정 gemini skills 디렉토리에는 네임스페이스 링크가 생성되지 않는다 (#1787)
    [ ! -e "${gem_dir}/gh-flow:issue" ]
}

@test "sync-gemini-skills-namespace: dry-run does not create symlinks (#1784)" {
    run_sync --dry-run
    assert_success
    assert_output --partial "DRY-RUN 모드"
    assert_output --partial "gh-flow:issue"

    local agy_dir="${FIXTURE_HOME}/.gemini/config/skills"
    [ ! -e "${agy_dir}/gh-flow:issue" ]
}

@test "sync-gemini-skills-namespace: idempotent on multiple runs (#1784)" {
    run_sync
    assert_success

    run_sync
    assert_success
    assert_output --partial "유지 4개"
}

@test "sync-gemini-skills-namespace: prunes stale namespaced links (#1784)" {
    run_sync
    assert_success

    local agy_dir="${FIXTURE_HOME}/.gemini/config/skills"
    [ -L "${agy_dir}/gh-flow:autopilot" ]

    # Remove autopilot skill
    rm -rf "${WORKSPACE}/gh-flow-skills/skills/autopilot"

    run_sync
    assert_success
    [ ! -e "${agy_dir}/gh-flow:autopilot" ]
    [ -L "${agy_dir}/gh-flow:issue" ]
}

@test "sync-gemini-skills-namespace: skips worktree repos (#1784)" {
    mkdir -p "${WORKSPACE}/gh-flow-skills-issue-99-1/skills/shadowed"
    printf 'gitdir: elsewhere\n' > "${WORKSPACE}/gh-flow-skills-issue-99-1/.git"
    cat > "${WORKSPACE}/gh-flow-skills-issue-99-1/skills/shadowed/SKILL.md" <<'SKILLEOF'
---
name: shadowed
---
SKILLEOF

    run_sync
    assert_success

    local agy_dir="${FIXTURE_HOME}/.gemini/config/skills"
    [ ! -e "${agy_dir}/gh-flow:shadowed" ]
    [ ! -e "${agy_dir}/gh-flow-skills-issue-99-1:shadowed" ]
}
