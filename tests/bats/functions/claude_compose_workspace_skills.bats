#!/usr/bin/env bats
# tests/bats/functions/claude_compose_workspace_skills.bats
# Cover _claude_compose_workspace_skills — the issue #1652 helper that
# layers locally cloned marketplace repos (#1410 F-6) on top of the
# dotfiles entries _claude_compose_skills_dir already wrote. The
# dotfiles-only composition itself is covered by
# claude_compose_skills_dir.bats.

load '../test_helper'

setup() {
    setup_isolated_home
    SRC="$TEST_TEMP_HOME/src-skills"
    TGT="$TEST_TEMP_HOME/.claude/skills"
    WS="$TEST_TEMP_HOME/workspace"

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
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
# Compose the dotfiles SSOT first, exactly as _claude_account_setup_one does,
# then layer the workspace on top.
_claude_compose_skills_dir "\$1" "\$2"
_claude_compose_workspace_skills "\$2"
EOF
    chmod +x "$HELPER_SCRIPT"
}

teardown() {
    teardown_isolated_home
}

# Usage: seed_ws_repo <repo> <skill> [<skill>...]
seed_ws_repo() {
    local repo="$1"
    shift
    local skill
    for skill in "$@"; do
        mkdir -p "$WS/$repo/skills/$skill"
        : > "$WS/$repo/skills/$skill/SKILL.md"
    done
    # A real clone keeps .git as a directory (worktrees keep a file).
    mkdir -p "$WS/$repo/.git"
}

run_compose() {
    WORKSPACE_ROOT="$WS" run "$HELPER_SCRIPT" "$SRC" "$TGT"
}

@test "workspace skills are layered next to the dotfiles entries (#1652)" {
    seed_ws_repo "packaging-skills" "create" "rename-repo"

    run_compose
    assert_success

    # dotfiles entries survive, pointing at the dotfiles source.
    [ "$(readlink "$TGT/alpha")" = "$SRC/alpha" ]
    [ "$(readlink "$TGT/beta")" = "$SRC/beta" ]
    # workspace entries are added alongside.
    [ "$(readlink "$TGT/create")" = "$WS/packaging-skills/skills/create" ]
    [ "$(readlink "$TGT/rename-repo")" = "$WS/packaging-skills/skills/rename-repo" ]
}

@test "absent workspace root is a silent no-op (#1652 Error Case 1)" {
    [ ! -d "$WS" ]

    run_compose
    assert_success

    [ -L "$TGT/alpha" ] && [ -L "$TGT/beta" ]
}

@test "repo without a skills/ dir is skipped (#1652 Error Case 2)" {
    mkdir -p "$WS/not-a-skill-repo/docs"
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success

    [ -L "$TGT/create" ]
    [ ! -e "$TGT/not-a-skill-repo" ]
    [ ! -e "$TGT/docs" ]
}

@test "skills/ entry without SKILL.md is not a source (#1652)" {
    seed_ws_repo "packaging-skills" "create"
    mkdir -p "$WS/packaging-skills/skills/_shared"

    run_compose
    assert_success

    [ -L "$TGT/create" ]
    [ ! -e "$TGT/_shared" ]
}

@test "a dotfiles skill of the same name is never repointed (#1652 NF-1)" {
    seed_ws_repo "packaging-skills" "alpha"

    run_compose
    assert_success

    [ "$(readlink "$TGT/alpha")" = "$SRC/alpha" ]
}

@test "linked git worktrees are skipped so they cannot shadow the clone (#1652)" {
    seed_ws_repo "packaging-skills" "create"
    # A linked worktree: same skills, `.git` is a file, and its name sorts
    # ahead of the clone under LC_ALL=C ('-' < '/').
    mkdir -p "$WS/packaging-skills-feat-1/skills/create"
    : > "$WS/packaging-skills-feat-1/skills/create/SKILL.md"
    printf 'gitdir: /elsewhere\n' > "$WS/packaging-skills-feat-1/.git"

    run_compose
    assert_success

    [ "$(readlink "$TGT/create")" = "$WS/packaging-skills/skills/create" ]
}

@test "composition is idempotent on repeat runs (#1652)" {
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success
    before="$(ls -la "$TGT")"

    run_compose
    assert_success
    after="$(ls -la "$TGT")"

    [ "$before" = "$after" ]
}

@test "stale workspace link is pruned when its repo disappears (#1652 NF-3)" {
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success
    [ -L "$TGT/create" ]

    rm -rf "$WS/packaging-skills"

    run_compose
    assert_success
    [ ! -e "$TGT/create" ]
    # dotfiles entries are untouched by the workspace prune.
    [ -L "$TGT/alpha" ]
}

@test "a repo rename converges in a single run (#1652)" {
    seed_ws_repo "old-name-skills" "create"

    run_compose
    assert_success
    [ "$(readlink "$TGT/create")" = "$WS/old-name-skills/skills/create" ]

    mv "$WS/old-name-skills" "$WS/new-name-skills"

    run_compose
    assert_success
    [ "$(readlink "$TGT/create")" = "$WS/new-name-skills/skills/create" ]
}

@test "symlinks outside the workspace root are never pruned (#1652)" {
    mkdir -p "$TEST_TEMP_HOME/overlay/marketplace-skill"
    mkdir -p "$TGT"
    ln -s "$TEST_TEMP_HOME/overlay/marketplace-skill" "$TGT/marketplace-skill"
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success
    [ -L "$TGT/marketplace-skill" ]

    # Even once its own target is gone, a non-workspace link is left alone.
    rm -rf "$TEST_TEMP_HOME/overlay/marketplace-skill"
    run_compose
    assert_success
    [ -L "$TGT/marketplace-skill" ]
}

@test "WORKSPACE_ROOT of \$HOME is refused as too broad (#1652 safety)" {
    seed_ws_repo "packaging-skills" "create"

    WORKSPACE_ROOT="$HOME" run "$HELPER_SCRIPT" "$SRC" "$TGT"
    assert_success

    [ ! -e "$TGT/create" ]
    [ -L "$TGT/alpha" ]
}
