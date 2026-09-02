#!/usr/bin/env bats
# tests/bats/functions/claude_compose_workspace_skills.bats
# Cover _claude_compose_workspace_skills — the issue #1652 helper that
# composes the locally cloned marketplace repos (#1410 F-6) into a
# harness skills dir. Since #1680 deleted the dotfiles `claude/skills/`
# tree this is the *only* skill source, so the helper also owns the
# target-directory migrations that _claude_compose_skills_dir used to
# perform (now _claude_prepare_skills_dir, covered at the bottom).

load '../test_helper'

setup() {
    setup_isolated_home
    TGT="$TEST_TEMP_HOME/.claude/skills"
    WS="$TEST_TEMP_HOME/workspace"

    HELPER_SCRIPT="$(mktemp "$TEST_TEMP_HOME/run.XXXXXX.sh")"
    cat > "$HELPER_SCRIPT" <<EOF
#!/bin/bash
set -e
export DOTFILES_FORCE_INIT=1
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/mount.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
_claude_compose_workspace_skills "\$1"
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
    WORKSPACE_ROOT="$WS" run "$HELPER_SCRIPT" "$TGT"
}

@test "workspace skills are composed as entry-level symlinks (#1652 / #1680)" {
    seed_ws_repo "packaging-skills" "create" "rename-repo"

    run_compose
    assert_success

    [ "$(readlink "$TGT/create")" = "$WS/packaging-skills/skills/create" ]
    [ "$(readlink "$TGT/rename-repo")" = "$WS/packaging-skills/skills/rename-repo" ]
}

@test "absent workspace root is a silent no-op (#1652 Error Case 1)" {
    [ ! -d "$WS" ]

    run_compose
    assert_success

    # The target is still normalized into a real composition directory —
    # it just gets no entries.
    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -z "$(find "$TGT" -mindepth 1 -maxdepth 1)" ]
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

@test "an overlay entry of the same name is never repointed (#1652 NF-1)" {
    # A marketplace overlay (or any externally added entry) owns the name
    # first; the workspace pass must leave it exactly as it is.
    mkdir -p "$TEST_TEMP_HOME/overlay/create" "$TGT"
    ln -s "$TEST_TEMP_HOME/overlay/create" "$TGT/create"
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success

    [ "$(readlink "$TGT/create")" = "$TEST_TEMP_HOME/overlay/create" ]
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

@test "every skills-composing site goes through the workspace pass (#1652 / #1680)" {
    # agy BLOCKER on PR #1670: the internal/single-account branch of
    # claude/setup.sh composes skills directly instead of going through
    # _claude_account_setup_one, so a workspace call has to appear in BOTH
    # files or single-account PCs (the company setup) silently get no skills
    # at all. #1680 removed the dotfiles pass, so this call is now the *only*
    # thing that ever writes a harness skills dir.
    #
    # Asserted per file rather than as one total: a bare count says nothing
    # about *which* file lost its call, which is exactly the failure #1670
    # shipped. The number of callers inside claude.sh is free to grow
    # (_claude_account_setup_one and claude_init both compose today).
    local setup="${_BATS_REAL_DOTFILES_ROOT}/claude/setup.sh"
    local integ="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"

    local f
    for f in "$setup" "$integ"; do
        run grep -c '^[[:space:]]*_claude_compose_workspace_skills ' "$f"
        assert_success
        [ "$output" -ge 1 ] || fail "no workspace compose call in $f"
    done

    # And the retired dotfiles composer must not creep back in.
    run grep -n '_claude_compose_skills_dir' "$setup" "$integ"
    assert_failure
}

@test "missing skill_sources.sh warns instead of silently no-opping (#1652 / #724)" {
    seed_ws_repo "packaging-skills" "create"

    # Same helper, minus the skill_sources.sh source line.
    local no_lib="$TEST_TEMP_HOME/no-lib.sh"
    grep -v 'functions/skill_sources.sh' "$HELPER_SCRIPT" > "$no_lib"
    chmod +x "$no_lib"

    WORKSPACE_ROOT="$WS" run "$no_lib" "$TGT"
    assert_success
    assert_output --partial "workspace skill sources unavailable"

    [ ! -e "$TGT/create" ]
}

@test "WORKSPACE_ROOT of \$HOME is refused as too broad (#1652 safety)" {
    seed_ws_repo "packaging-skills" "create"

    WORKSPACE_ROOT="$HOME" run "$HELPER_SCRIPT" "$TGT"
    assert_success

    [ ! -e "$TGT/create" ]
}

# ---------------------------------------------------------------------
# Target-directory migrations (_claude_prepare_skills_dir, #707 F-8).
# These used to live in claude_compose_skills_dir.bats; #1680 retired that
# function and folded its prologue into the workspace composer, so the
# migrations are exercised through the composer now.
# ---------------------------------------------------------------------

@test "legacy dir-symlink target is migrated to a real composition dir (#707 F-8)" {
    mkdir -p "$TEST_TEMP_HOME/.claude" "$TEST_TEMP_HOME/legacy-skills"
    ln -s "$TEST_TEMP_HOME/legacy-skills" "$TGT"
    [ -L "$TGT" ]
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ "$(readlink "$TGT/create")" = "$WS/packaging-skills/skills/create" ]
}

@test "a dir-symlink to the deleted dotfiles SSOT is migrated, not preserved (#1680)" {
    # The #1680 cutover leaves this exact shape on existing machines: a
    # symlink whose target (dotfiles/claude/skills) no longer exists.
    mkdir -p "$TEST_TEMP_HOME/.claude"
    ln -s "$TEST_TEMP_HOME/gone/claude/skills" "$TGT"
    [ -L "$TGT" ] && [ ! -e "$TGT" ]
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -L "$TGT/create" ]
}

@test "an unexpected regular file at the target is backed up, not clobbered (#707 F-8)" {
    mkdir -p "$TEST_TEMP_HOME/.claude"
    printf 'user data\n' > "$TGT"
    seed_ws_repo "packaging-skills" "create"

    run_compose
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -L "$TGT/create" ]
    run bash -c "cat \"$TEST_TEMP_HOME/.claude\"/skills-*-original"
    assert_success
    assert_output --partial "user data"
}
