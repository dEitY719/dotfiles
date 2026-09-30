#!/usr/bin/env bats
# tests/bats/functions/claude_accounts_link.bats
# Cover `claude-accounts link / unlink / link --list` (issue #1847): fan an
# external skill source out into every ~/.claude-*/skills account dir.

load '../test_helper'

setup() {
    setup_isolated_home
    WS="$TEST_TEMP_HOME/workspace"
    LAND="$TEST_TEMP_HOME/.claude/skills"
    A1="$TEST_TEMP_HOME/.claude-personal/skills"
    A2="$TEST_TEMP_HOME/.claude-work1/skills"
    mkdir -p "$LAND" "$A1" "$A2" \
        "$TEST_TEMP_HOME/.claude-shared/skills" \
        "$TEST_TEMP_HOME/.claude-backups/skills"

    # 3rd-party installer layout: real skill under ~/.agents, relative link
    # in the landing dir (the find-skills case from the issue).
    SRC="$TEST_TEMP_HOME/.agents/skills/find-skills"
    mkdir -p "$SRC"
    : > "$SRC/SKILL.md"
    ln -s ../../.agents/skills/find-skills "$LAND/find-skills"
    SRC_REAL="$(readlink -f "$SRC")"

    HELPER_SCRIPT="$(mktemp "$TEST_TEMP_HOME/run.XXXXXX.sh")"
    cat > "$HELPER_SCRIPT" <<EOF
#!/bin/bash
export DOTFILES_FORCE_INIT=1
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/mount.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
if [ "\$1" = "--compose" ]; then
    _claude_compose_workspace_skills "\$2"
else
    claude_accounts "\$@"
fi
EOF
    chmod +x "$HELPER_SCRIPT"
}

teardown() {
    teardown_isolated_home
}

ca() {
    WORKSPACE_ROOT="$WS" run "$HELPER_SCRIPT" "$@"
}

@test "link <path> creates absolute symlinks in every account (AC-1, NF-2)" {
    ca link "$SRC"
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
    [ "$(readlink "$A2/find-skills")" = "$SRC_REAL" ]
    # -shared / -backups are not accounts (F-4)
    [ ! -e "$TEST_TEMP_HOME/.claude-shared/skills/find-skills" ]
    [ ! -e "$TEST_TEMP_HOME/.claude-backups/skills/find-skills" ]
}

@test "link <name> resolves to ~/.claude/skills/<name> as an absolute path (AC-3)" {
    ca link find-skills
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
    [ "$(readlink "$A2/find-skills")" = "$SRC_REAL" ]
}

@test "--name overrides the link name" {
    ca link "$SRC" --name fs
    assert_success
    [ "$(readlink "$A1/fs")" = "$SRC_REAL" ]
    [ ! -e "$A1/find-skills" ]
}

@test "link --dry-run does not touch the filesystem (AC-7)" {
    ca link "$SRC" --dry-run
    assert_success
    [ ! -e "$A1/find-skills" ] && [ ! -L "$A1/find-skills" ]
    [ ! -e "$A2/find-skills" ] && [ ! -L "$A2/find-skills" ]
}

@test "no-arg link is a dry-run; --apply links the landing entries (AC-2)" {
    ca link
    assert_success
    assert_output --partial "find-skills"
    [ ! -L "$A1/find-skills" ] && [ ! -L "$A2/find-skills" ]

    ca link --apply
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
    [ "$(readlink "$A2/find-skills")" = "$SRC_REAL" ]
}

@test "no-arg link skips landing entries that point into the workspace (F-1)" {
    mkdir -p "$WS/repo/skills/wsk"
    : > "$WS/repo/skills/wsk/SKILL.md"
    ln -s "$WS/repo/skills/wsk" "$LAND/wsk"

    ca link --apply
    assert_success
    [ ! -e "$A1/wsk" ] && [ ! -L "$A1/wsk" ]
    [ -L "$A1/find-skills" ]
}

@test "no-arg link with an empty landing dir is an info no-op" {
    rm -f "$LAND/find-skills"
    ca link
    assert_success
}

@test "re-running link reports already linked and changes nothing (AC-4)" {
    ca link "$SRC"
    assert_success
    ca link "$SRC"
    assert_success
    assert_output --partial "already linked"
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
}

@test "a real dir in one account is skipped, the others still link (AC-5)" {
    mkdir -p "$A1/find-skills"
    : > "$A1/find-skills/keep"

    ca link "$SRC"
    assert_success
    [ -d "$A1/find-skills" ] && [ ! -L "$A1/find-skills" ]
    [ -f "$A1/find-skills/keep" ]
    [ "$(readlink "$A2/find-skills")" = "$SRC_REAL" ]

    # --force never replaces a real dir either
    ca link "$SRC" --force
    [ -d "$A1/find-skills" ] && [ ! -L "$A1/find-skills" ]
    [ -f "$A1/find-skills/keep" ]
}

@test "a symlink to another target is skipped unless --force (F-5)" {
    mkdir -p "$TEST_TEMP_HOME/other"
    ln -s "$TEST_TEMP_HOME/other" "$A1/find-skills"

    ca link "$SRC"
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$TEST_TEMP_HOME/other" ]

    ca link "$SRC" --force
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
}

@test "source without SKILL.md fails and touches no account (Error Case 1)" {
    mkdir -p "$TEST_TEMP_HOME/notaskill"
    ca link "$TEST_TEMP_HOME/notaskill"
    assert_failure
    [ -z "$(find "$A1" "$A2" -mindepth 1)" ]
}

@test "unknown name fails (Error Case 2)" {
    ca link no-such-skill
    assert_failure
    [ -z "$(find "$A1" "$A2" -mindepth 1)" ]
}

@test "zero target accounts warns and returns 0 (Error Case 4)" {
    rm -rf "$TEST_TEMP_HOME/.claude-personal" "$TEST_TEMP_HOME/.claude-work1"
    rm -rf "$LAND"
    ca link "$SRC"
    assert_success
    assert_output --partial "claude-accounts setup"
}

@test "single-account PC targets ~/.claude/skills only (F-4)" {
    rm -rf "$TEST_TEMP_HOME/.claude-personal" "$TEST_TEMP_HOME/.claude-work1"
    ca link "$SRC" --name fs
    assert_success
    [ "$(readlink "$LAND/fs")" = "$SRC_REAL" ]
}

@test "unlink removes symlinks and never deletes a real dir (AC-6)" {
    ca link "$SRC"
    rm -f "$A1/find-skills"
    mkdir -p "$A1/find-skills"
    : > "$A1/find-skills/keep"

    ca unlink find-skills
    assert_success
    [ -f "$A1/find-skills/keep" ]
    [ ! -e "$A2/find-skills" ] && [ ! -L "$A2/find-skills" ]
}

@test "link --list shows external links and marks broken ones (AC-8)" {
    ca link "$SRC"
    ln -s "$TEST_TEMP_HOME/gone" "$A1/dead"
    mkdir -p "$WS/repo/skills/wsk"
    ln -s "$WS/repo/skills/wsk" "$A1/wsk"

    ca link --list
    assert_success
    assert_output --partial "find-skills"
    assert_output --regexp "BROKEN.*dead"
    refute_output --partial "wsk"
}

@test "workspace compose afterwards keeps the external link (AC-9)" {
    mkdir -p "$WS/repo/skills/wsk" "$WS/repo/.git"
    : > "$WS/repo/skills/wsk/SKILL.md"
    ca link "$SRC"

    ca --compose "$A1"
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
    [ -L "$A1/wsk" ]
}

@test "link rejects a second positional <src> and touches nothing (PR #1848 review)" {
    ca link "$SRC" other-skill
    assert_failure
    [ ! -e "$A1/find-skills" ]
    [ ! -e "$A2/find-skills" ]
}

@test "a broken account skills symlink is skipped, not linked into (PR #1848 review)" {
    rm -rf "$A2" && ln -s "$TEST_TEMP_HOME/gone" "$A2"
    ca link "$SRC"
    assert_success
    [ "$(readlink "$A1/find-skills")" = "$SRC_REAL" ]
}
