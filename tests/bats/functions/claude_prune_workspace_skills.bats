#!/usr/bin/env bats
# tests/bats/functions/claude_prune_workspace_skills.bats
# Cover _claude_prune_workspace_skills. Claude Code loads the workspace
# marketplace repos as plugins (claude/plugin/plugins.json — the single SSOT
# for Claude Code skills), so the old flat composition (#1652 / #1680,
# _claude_compose_workspace_skills) would register every skill a second time
# as an un-namespaced command. The helper therefore composes nothing: it only
# prunes the flat workspace links that composition left behind, keeps every
# other entry, and still owns the target-directory migrations
# (_claude_prepare_skills_dir, covered at the bottom).

load '../test_helper'

setup() {
    setup_isolated_home
    TGT="$TEST_TEMP_HOME/.claude/skills"
    WS="$TEST_TEMP_HOME/workspace"

    HELPER_SCRIPT="$(mktemp "$TEST_TEMP_HOME/run.XXXXXX.sh")"
    cat > "$HELPER_SCRIPT" <<EOS
#!/bin/bash
set -e
export DOTFILES_FORCE_INIT=1
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/mount.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
for _t in "\$@"; do
    _claude_prune_workspace_skills "\$_t"
done
echo "PRUNED_TOTAL=\${CLAUDE_WS_SKILLS_PRUNED:-0}"
EOS
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

run_prune() {
    WORKSPACE_ROOT="$WS" run "$HELPER_SCRIPT" "$TGT"
}

@test "workspace skills are NOT composed into Claude Code skills dirs (plugins are the SSOT)" {
    seed_ws_repo "packaging-skills" "create" "rename-repo"

    run_prune
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ ! -e "$TGT/create" ] && [ ! -L "$TGT/create" ]
    [ ! -e "$TGT/rename-repo" ] && [ ! -L "$TGT/rename-repo" ]
    [ -z "$(find "$TGT" -mindepth 1 -maxdepth 1)" ]
}

@test "existing workspace links are pruned, including dangling ones" {
    seed_ws_repo "packaging-skills" "create"
    seed_ws_repo "gh-flow-skills" "issue"
    mkdir -p "$TGT"
    # Live link left by the old composition.
    ln -s "$WS/packaging-skills/skills/create" "$TGT/create"
    # Dangling: the skill dir was removed but the repo is still there.
    ln -s "$WS/gh-flow-skills/skills/gone" "$TGT/gone"
    # Dangling: the whole repo was removed (readlink -f cannot resolve it).
    ln -s "$WS/removed-repo/skills/old" "$TGT/old"
    # Relative spelling of a workspace link.
    ln -s ../../workspace/gh-flow-skills/skills/issue "$TGT/issue"

    run_prune
    assert_success
    assert_output --partial "PRUNED_TOTAL=4"

    local n
    for n in create gone old issue; do
        [ ! -e "$TGT/$n" ] && [ ! -L "$TGT/$n" ] || fail "$n was not pruned"
    done
    # The workspace sources themselves are never touched.
    [ -f "$WS/packaging-skills/skills/create/SKILL.md" ]
}

@test "non-workspace symlinks, real dirs and files are preserved" {
    seed_ws_repo "packaging-skills" "create"
    mkdir -p "$TGT" "$TEST_TEMP_HOME/elsewhere/graphify"
    ln -s "$WS/packaging-skills/skills/create" "$TGT/create"
    # Symlink outside the workspace (graphify / claude-accounts link).
    ln -s "$TEST_TEMP_HOME/elsewhere/graphify" "$TGT/graphify"
    # Dangling symlink outside the workspace — not ours to clean.
    ln -s "$TEST_TEMP_HOME/elsewhere/vanished" "$TGT/vanished"
    # Real directories and a plain file.
    mkdir -p "$TGT/agentmemory-recall" "$TGT/synced" "$TGT/.trash"
    printf 'user data\n' > "$TGT/agentmemory-recall/SKILL.md"
    printf 'note\n' > "$TGT/README.txt"

    run_prune
    assert_success
    assert_output --partial "PRUNED_TOTAL=1"

    [ ! -L "$TGT/create" ]
    [ "$(readlink "$TGT/graphify")" = "$TEST_TEMP_HOME/elsewhere/graphify" ]
    [ "$(readlink "$TGT/vanished")" = "$TEST_TEMP_HOME/elsewhere/vanished" ]
    [ -d "$TGT/agentmemory-recall" ] && [ ! -L "$TGT/agentmemory-recall" ]
    grep -q "user data" "$TGT/agentmemory-recall/SKILL.md"
    [ -d "$TGT/synced" ] && [ -d "$TGT/.trash" ]
    grep -q "note" "$TGT/README.txt"
}

@test "a real directory named like a workspace skill is never removed" {
    seed_ws_repo "packaging-skills" "create"
    mkdir -p "$TGT/create"
    printf 'local copy\n' > "$TGT/create/SKILL.md"

    run_prune
    assert_success

    [ -d "$TGT/create" ] && [ ! -L "$TGT/create" ]
    grep -q "local copy" "$TGT/create/SKILL.md"
}

@test "links via the resolved spelling of a symlinked workspace root are pruned" {
    seed_ws_repo "packaging-skills" "create"
    # WORKSPACE_ROOT is a symlink; the stale link uses the real path.
    ln -s "$WS" "$TEST_TEMP_HOME/ws-alias"
    mkdir -p "$TGT"
    ln -s "$(readlink -f "$WS")/packaging-skills/skills/create" "$TGT/create"

    WORKSPACE_ROOT="$TEST_TEMP_HOME/ws-alias" run "$HELPER_SCRIPT" "$TGT"
    assert_success
    [ ! -e "$TGT/create" ] && [ ! -L "$TGT/create" ]
}

@test "pruning is idempotent on repeat runs" {
    seed_ws_repo "packaging-skills" "create"
    mkdir -p "$TGT" "$TEST_TEMP_HOME/elsewhere/graphify" "$TGT/synced"
    ln -s "$WS/packaging-skills/skills/create" "$TGT/create"
    ln -s "$TEST_TEMP_HOME/elsewhere/graphify" "$TGT/graphify"

    run_prune
    assert_success
    assert_output --partial "PRUNED_TOTAL=1"
    before="$(ls -la "$TGT")"

    run_prune
    assert_success
    assert_output --partial "PRUNED_TOTAL=0"
    refute_output --partial "removed workspace skill link"
    after="$(ls -la "$TGT")"

    [ "$before" = "$after" ]
}

@test "pruned count accumulates across accounts in CLAUDE_WS_SKILLS_PRUNED (#997 summary)" {
    seed_ws_repo "packaging-skills" "create" "rename-repo"
    local t2="$TEST_TEMP_HOME/.claude-work/skills"
    mkdir -p "$TGT" "$t2"
    ln -s "$WS/packaging-skills/skills/create" "$TGT/create"
    ln -s "$WS/packaging-skills/skills/create" "$t2/create"
    ln -s "$WS/packaging-skills/skills/rename-repo" "$t2/rename-repo"

    WORKSPACE_ROOT="$WS" run "$HELPER_SCRIPT" "$TGT" "$t2"
    assert_success
    assert_output --partial "PRUNED_TOTAL=3"
}

@test "absent workspace root is a silent no-op that still prepares the dir" {
    [ ! -d "$WS" ]

    run_prune
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    [ -z "$(find "$TGT" -mindepth 1 -maxdepth 1)" ]
}

@test "every Claude Code skills site prunes and none composes workspace skills" {
    # The internal/single-account branch of claude/setup.sh does not go
    # through _claude_account_setup_one (agy BLOCKER on PR #1670), so the
    # cleanup call has to appear in BOTH files or single-account PCs keep
    # the duplicate un-namespaced skills. Asserted per file so a failure
    # names the file that lost its call.
    local setup="${_BATS_REAL_DOTFILES_ROOT}/claude/setup.sh"
    local integ="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"

    local f
    for f in "$setup" "$integ"; do
        run grep -c '^[[:space:]]*_claude_prune_workspace_skills ' "$f"
        assert_success
        [ "$output" -ge 1 ] || fail "no workspace prune call in $f"
    done

    # Neither the retired workspace composer nor the older dotfiles composer
    # may creep back in — plugins are the single SSOT for Claude Code.
    run grep -nE '^[[:space:]]*_claude_compose_(workspace_skills|skills_dir)\b' "$setup" "$integ"
    assert_failure
    run grep -nE '^_claude_compose_(workspace_skills|skills_dir)\(\)' "$integ"
    assert_failure
}

@test "missing skill_sources.sh warns instead of silently no-opping (#1652 / #724)" {
    seed_ws_repo "packaging-skills" "create"
    mkdir -p "$TGT"
    ln -s "$WS/packaging-skills/skills/create" "$TGT/create"

    # Same helper, minus the skill_sources.sh source line.
    local no_lib="$TEST_TEMP_HOME/no-lib.sh"
    grep -v 'functions/skill_sources.sh' "$HELPER_SCRIPT" > "$no_lib"
    chmod +x "$no_lib"

    WORKSPACE_ROOT="$WS" run "$no_lib" "$TGT"
    assert_success
    assert_output --partial "workspace skill sources unavailable"

    # Without a root it cannot tell ours from theirs, so nothing is removed.
    [ -L "$TGT/create" ]
}

@test "WORKSPACE_ROOT of \$HOME is refused as too broad — nothing is pruned (#1652 safety)" {
    mkdir -p "$TGT" "$TEST_TEMP_HOME/elsewhere/graphify"
    ln -s "$TEST_TEMP_HOME/elsewhere/graphify" "$TGT/graphify"

    WORKSPACE_ROOT="$HOME" run "$HELPER_SCRIPT" "$TGT"
    assert_success

    [ -L "$TGT/graphify" ]
}

# ---------------------------------------------------------------------
# Target-directory migrations (_claude_prepare_skills_dir, #707 F-8).
# skills/ stays a real directory so externally added links still work.
# ---------------------------------------------------------------------

@test "legacy dir-symlink target is migrated to a real directory (#707 F-8)" {
    mkdir -p "$TEST_TEMP_HOME/.claude" "$TEST_TEMP_HOME/legacy-skills"
    ln -s "$TEST_TEMP_HOME/legacy-skills" "$TGT"
    [ -L "$TGT" ]

    run_prune
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    # The old target's contents are left alone.
    [ -d "$TEST_TEMP_HOME/legacy-skills" ]
}

@test "a dir-symlink to the deleted dotfiles SSOT is migrated, not preserved (#1680)" {
    mkdir -p "$TEST_TEMP_HOME/.claude"
    ln -s "$TEST_TEMP_HOME/gone/claude/skills" "$TGT"
    [ -L "$TGT" ] && [ ! -e "$TGT" ]

    run_prune
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
}

@test "an unexpected regular file at the target is backed up, not clobbered (#707 F-8)" {
    mkdir -p "$TEST_TEMP_HOME/.claude"
    printf 'user data\n' > "$TGT"

    run_prune
    assert_success

    [ -d "$TGT" ] && [ ! -L "$TGT" ]
    run bash -c "cat \"$TEST_TEMP_HOME/.claude\"/skills-*-original"
    assert_success
    assert_output --partial "user data"
}
