#!/usr/bin/env bats
# tests/bats/integrations/claude_accounts_repair.bats
#
# `claude_accounts_repair` is the one-shot cleanup helper for
# worktree-tainted ~/.claude-*/ symlinks (issue #589, Option C).
#
# Strategy: build a fake "worktree path was rm -rf'd" scenario inside
# $TEST_TEMP_HOME by laying down symlinks under ~/.claude-personal/ that
# point at a non-existent /tmp path. Run the repair and assert the
# symlinks now point at ${DOTFILES_ROOT}/claude/.

load '../test_helper'

setup() {
    setup_isolated_home

    # Stand up a fake "worktree path" that does not exist on disk —
    # mirrors the post-`git worktree remove` state described in #589.
    FAKE_WT="/tmp/dotfiles-fake-worktree-DOES-NOT-EXIST"

    # ~/.claude-personal/ with the well-known symlink set.
    PERSONAL="$HOME/.claude-personal"
    mkdir -p "$PERSONAL/projects/GLOBAL"
    ln -s "$FAKE_WT/claude/settings.json"          "$PERSONAL/settings.json"
    ln -s "$FAKE_WT/claude/statusline-command.sh"  "$PERSONAL/statusline-command.sh"
    ln -s "$FAKE_WT/claude/skills"                 "$PERSONAL/skills"
    ln -s "$FAKE_WT/claude/docs"                   "$PERSONAL/docs"
    ln -s "$FAKE_WT/claude/global-memory"          "$PERSONAL/projects/GLOBAL/memory"

    # Also stage a "canonical" symlink on ~/.claude-work to prove
    # `repair` leaves clean entries alone.
    WORK="$HOME/.claude-work"
    mkdir -p "$WORK"
    ln -s "$DOTFILES_ROOT/claude/settings.json" "$WORK/settings.json"
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# repair (apply) — dangling symlinks rebound to canonical DOTFILES_ROOT
# ---------------------------------------------------------------------------

@test "claude_accounts_repair: rebinds dangling settings.json to canonical root" {
    run_in_bash 'claude_accounts_repair >/dev/null 2>&1; readlink "$HOME/.claude-personal/settings.json"'
    assert_success
    assert_output "$DOTFILES_ROOT/claude/settings.json"
}

@test "claude_accounts_repair: rebinds dangling skills (directory symlink) too" {
    run_in_bash 'claude_accounts_repair >/dev/null 2>&1; readlink "$HOME/.claude-personal/skills"'
    assert_success
    assert_output "$DOTFILES_ROOT/claude/skills"
}

@test "claude_accounts_repair: rebinds nested projects/GLOBAL/memory" {
    run_in_bash 'claude_accounts_repair >/dev/null 2>&1; readlink "$HOME/.claude-personal/projects/GLOBAL/memory"'
    assert_success
    assert_output "$DOTFILES_ROOT/claude/global-memory"
}

@test "claude_accounts_repair: leaves an already-canonical symlink alone" {
    run_in_bash 'claude_accounts_repair >/dev/null 2>&1; readlink "$HOME/.claude-work/settings.json"'
    assert_success
    assert_output "$DOTFILES_ROOT/claude/settings.json"
}

@test "claude_accounts_repair: reports skipped count for canonical entries" {
    run_in_bash 'claude_accounts_repair 2>&1'
    assert_success
    assert_output --partial "already canonical"
}

# ---------------------------------------------------------------------------
# repair --dry-run — reports without mutating
# ---------------------------------------------------------------------------

@test "claude_accounts_repair --dry-run: keeps the dangling symlink in place" {
    run_in_bash 'claude_accounts_repair --dry-run >/dev/null 2>&1; readlink "$HOME/.claude-personal/settings.json"'
    assert_success
    # Original target is untouched in dry-run.
    refute_output "$DOTFILES_ROOT/claude/settings.json"
    assert_output --partial "dotfiles-fake-worktree-DOES-NOT-EXIST"
}

@test "claude_accounts_repair --dry-run: mentions dry-run mode in output" {
    run_in_bash 'claude_accounts_repair --dry-run 2>&1'
    assert_success
    assert_output --partial "Mode: dry-run"
    assert_output --partial "would repair"
}

# ---------------------------------------------------------------------------
# Idempotency — second run is a no-op
# ---------------------------------------------------------------------------

@test "claude_accounts_repair: second run is a no-op (everything canonical)" {
    run_in_bash '
        claude_accounts_repair >/dev/null 2>&1
        claude_accounts_repair 2>&1 | grep -E "0 rebound|Repair complete"
    '
    assert_success
}
