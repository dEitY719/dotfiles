#!/usr/bin/env bats
# tests/bats/functions/git_worktree_spawn.bats
# Tests for `gwt spawn --ai` flag (issue #162).
# Focuses on argument parsing + validation paths that do NOT require tmux
# or a real worktree layout — the interesting behavioral change is the
# decoupling of worktree <name> from the tmux agent name.

load '../test_helper'

_setup_fake_main_repo() {
    FAKE_REPO="$TEST_TEMP_HOME/fake-main"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    git init -q --initial-branch=main "$FAKE_REPO"
    (
        cd "$FAKE_REPO"
        echo base >base.txt
        git add base.txt
        git commit -q -m base
    )
}

setup() {
    setup_isolated_home
    _setup_fake_main_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

@test "bash: git_worktree_spawn function exists" {
    run_in_bash 'declare -f git_worktree_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: spawn --help mentions --ai flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--ai"
    assert_output --partial "claude"
}

@test "bash: spawn --help no longer shows the <name>-yolo caveat" {
    # The old caveat read "The pane runs '<name>-yolo'". After the agent
    # decoupling, tmux windows run '<agent>-yolo' regardless of <name>.
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    refute_output --partial "<name>-yolo"
}

@test "bash: spawn rejects unknown agent when --tmux is used" {
    # --tmux triggers the agent validation path. Use a name inside an
    # isolated dir so we reach validation without spawning anything real.
    # The key assertion: an unknown agent must produce a helpful error.
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --ai notarealagent 2>&1
    "
    assert_failure
    assert_output --partial "Unknown agent: notarealagent"
    assert_output --partial "claude"
}

@test "zsh: git_worktree_spawn function exists" {
    run_in_zsh 'declare -f git_worktree_spawn >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: spawn --help mentions --ai flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--ai"
}

@test "bash: spawn --help mentions --launch flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--launch"
}

@test "bash: spawn rejects --tmux and --launch together" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --launch 2>&1
    "
    assert_failure
    assert_output --partial "mutually exclusive"
}

@test "zsh: spawn rejects --tmux and --launch together" {
    run_in_zsh "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --launch 2>&1
    "
    assert_failure
    assert_output --partial "mutually exclusive"
}

@test "bash: spawn rejects unknown agent when --launch is used" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --ai notarealagent 2>&1
    "
    assert_failure
    assert_output --partial "Unknown agent: notarealagent"
}

@test "zsh: spawn rejects unknown agent when --launch is used" {
    run_in_zsh "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --ai notarealagent 2>&1
    "
    assert_failure
    assert_output --partial "Unknown agent: notarealagent"
}

@test "zsh: spawn --help mentions --launch flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--launch"
}

@test "bash: spawn auto-increments when branch exists without worktree" {
    run_in_bash "
        cd '$FAKE_REPO' || exit 1
        git branch wt/feat/1
        git_worktree_spawn feat 2>&1
        git show-ref --verify --quiet refs/heads/wt/feat/2 && echo BRANCH2_OK
        [ -d '$TEST_TEMP_HOME/fake-main-feat-2' ] && echo PATH2_OK
    "
    assert_success
    assert_output --partial "Branch: wt/feat/2"
    assert_output --partial "BRANCH2_OK"
    assert_output --partial "PATH2_OK"
}

# ---------------------------------------------------------------------------
# Issue #243: --launch must not depend on shell alias expansion.
# `_gwt_yolo_command <agent>` is a SSOT dispatch table that returns the
# actual command string to execute, bypassing the brittle alias path.
# ---------------------------------------------------------------------------

@test "bash: _gwt_yolo_command claude returns the function, not the alias name" {
    # Critical regression guard: must NOT return the alias 'claude-yolo'
    # (zsh inside function context fails to expand it — the bug from #243).
    run_in_bash '_gwt_yolo_command claude'
    assert_success
    assert_output "claude_yolo"
    refute_output --partial "claude-yolo"
}

@test "bash: _gwt_yolo_command codex returns the bypass-flagged command" {
    run_in_bash '_gwt_yolo_command codex'
    assert_success
    assert_output "codex --dangerously-bypass-approvals-and-sandbox"
}

@test "bash: _gwt_yolo_command gemini returns the yolo+skip-trust command" {
    run_in_bash '_gwt_yolo_command gemini'
    assert_success
    assert_output "gemini --approval-mode=yolo --skip-trust"
}

@test "bash: _gwt_yolo_command opencode returns the bare command" {
    run_in_bash '_gwt_yolo_command opencode'
    assert_success
    assert_output "opencode"
}

@test "bash: _gwt_yolo_command rejects unknown agent" {
    run_in_bash '_gwt_yolo_command notarealagent'
    assert_failure
}

@test "bash: _gwt_yolo_command --list lists supported agents (SSOT)" {
    # Co-located with the case body — call sites that print supported agents
    # must derive from this output to prevent drift from the dispatch table.
    run_in_bash '_gwt_yolo_command --list'
    assert_success
    assert_output "claude, codex, gemini, opencode"
}

@test "zsh: _gwt_yolo_command claude returns the function, not the alias name" {
    # The actual bug from #243 reproduced under zsh — this test must pass
    # before and after sourcing claude.sh, because we no longer rely on
    # alias expansion at all.
    run_in_zsh '_gwt_yolo_command claude'
    assert_success
    assert_output "claude_yolo"
    refute_output --partial "claude-yolo"
}

@test "zsh: _gwt_yolo_command codex returns the bypass-flagged command" {
    run_in_zsh '_gwt_yolo_command codex'
    assert_success
    assert_output "codex --dangerously-bypass-approvals-and-sandbox"
}

@test "zsh: _gwt_yolo_command gemini returns the yolo+skip-trust command" {
    run_in_zsh '_gwt_yolo_command gemini'
    assert_success
    assert_output "gemini --approval-mode=yolo --skip-trust"
}

@test "zsh: _gwt_yolo_command opencode returns the bare command" {
    run_in_zsh '_gwt_yolo_command opencode'
    assert_success
    assert_output "opencode"
}

@test "zsh: _gwt_yolo_command rejects unknown agent" {
    run_in_zsh '_gwt_yolo_command notarealagent'
    assert_failure
}

@test "zsh: _gwt_yolo_command --list lists supported agents (SSOT)" {
    run_in_zsh '_gwt_yolo_command --list'
    assert_success
    assert_output "claude, codex, gemini, opencode"
}

# ---------------------------------------------------------------------------
# Issue #295: gwt spawn --user <account> wires multi-account dispatch.
# Phase 1 (PR #292) introduced `claude_yolo --user <account>`. Phase 2 here
# threads --user through gwt spawn's --tmux/--launch paths so worktree
# creation can pick a non-default account in one shot.
# ---------------------------------------------------------------------------

@test "bash: spawn --help mentions --user flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--user"
    assert_output --partial "Claude account"
}

@test "zsh: spawn --help mentions --user flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--user"
}

@test "bash: _gwt_yolo_command claude with account appends --user" {
    # The launch dispatcher SSOT must thread account through, otherwise the
    # --launch path silently falls back to the default account.
    run_in_bash '_gwt_yolo_command claude work'
    assert_success
    assert_output "claude_yolo --user work"
}

@test "bash: _gwt_yolo_command claude with empty account stays unchanged" {
    # Regression guard: the no-account path (current default) must not
    # accidentally append a stray --user token.
    run_in_bash '_gwt_yolo_command claude ""'
    assert_success
    assert_output "claude_yolo"
}

@test "zsh: _gwt_yolo_command claude with account appends --user" {
    run_in_zsh '_gwt_yolo_command claude work'
    assert_success
    assert_output "claude_yolo --user work"
}

@test "bash: _gwt_yolo_command non-claude agents ignore account" {
    # Multi-account is claude-only — codex/gemini/opencode have no --user
    # support, so any value passed in 2nd position must be a no-op for them.
    run_in_bash '_gwt_yolo_command codex work'
    assert_success
    assert_output "codex --dangerously-bypass-approvals-and-sandbox"
}

@test "bash: spawn rejects --user without --tmux or --launch" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --user work 2>&1
    "
    assert_failure
    assert_output --partial "--user requires --tmux or --launch"
}

@test "bash: spawn rejects --user with non-claude agent (--launch)" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --ai codex --user work 2>&1
    "
    assert_failure
    assert_output --partial "--user is only supported with --ai claude"
}

@test "bash: spawn rejects --user with non-claude agent (--tmux)" {
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --tmux --ai gemini --user work 2>&1
    "
    assert_failure
    assert_output --partial "--user is only supported with --ai claude"
}

@test "bash: spawn rejects unknown account with helpful list" {
    # Reuses _claude_resolve_account's error message so the user sees the
    # same "Available: ..." hint as `claude_yolo --user xyz` would print.
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --user nonexistent-account 2>&1
    "
    assert_failure
    assert_output --partial "Unknown account: nonexistent-account"
    assert_output --partial "Available:"
}

@test "zsh: spawn rejects unknown account with helpful list" {
    run_in_zsh "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --user nonexistent-account 2>&1
    "
    assert_failure
    assert_output --partial "Unknown account: nonexistent-account"
}

@test "zsh: spawn rejects --user with non-claude agent" {
    run_in_zsh "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --ai codex --user work 2>&1
    "
    assert_failure
    assert_output --partial "--user is only supported with --ai claude"
}
