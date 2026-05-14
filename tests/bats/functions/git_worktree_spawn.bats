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

# ---------------------------------------------------------------------------
# Issue #640: --bg flag passes through to `claude --bg "<task>"`. Worktree
# is created then the agent's yolo command is dispatched in background
# mode so Agent View (`claude-yolo agents`) can see the session.
# ---------------------------------------------------------------------------

@test "bash: spawn --help mentions --bg flag" {
    run_in_bash 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--bg"
    assert_output --partial "Agent View"
}

@test "zsh: spawn --help mentions --bg flag" {
    run_in_zsh 'git_worktree_spawn --help'
    assert_success
    assert_output --partial "--bg"
}

@test "bash: spawn rejects --bg without --launch or --tmux" {
    # --bg only makes sense when something is being dispatched. Without
    # --launch/--tmux the worktree is created but nothing runs, so flag
    # the typo loudly.
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --bg 2>&1
    "
    assert_failure
    assert_output --partial "--bg requires --launch or --tmux"
}

@test "bash: spawn rejects --bg with --ai codex" {
    # Multi-agent guard: only claude has Agent View / --bg today.
    run_in_bash "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --launch --ai codex --bg 2>&1
    "
    assert_failure
    assert_output --partial "--bg is only supported with --ai claude"
}

@test "zsh: spawn rejects --bg without --launch or --tmux" {
    run_in_zsh "
        cd '${DOTFILES_ROOT}' || exit 1
        git_worktree_spawn issue-xyz --bg 2>&1
    "
    assert_failure
    assert_output --partial "--bg requires --launch or --tmux"
}

@test "bash: spawn --launch --bg dispatches claude_yolo --bg with empty task" {
    # End-to-end check via a fake claude_yolo shim. When --bg is given with
    # no task arg, the wrapper passes an empty string and lets claude itself
    # complain if needed. The marker uses '|' between args so word-splitting
    # cannot collapse `--bg` + empty string into a single token.
    run_in_bash "
        cd '$FAKE_REPO' || exit 1
        MARKER='$TEST_TEMP_HOME/spawn-bg-marker'
        export MARKER
        # Shadow claude_yolo with a recorder. _gwt_yolo_command returns the
        # literal 'claude_yolo', so once we redefine the function, eval'd
        # launch_cmd will dispatch into the recorder.
        claude_yolo() {
            local _cy_recorded=''
            for _a in \"\$@\"; do _cy_recorded=\"\${_cy_recorded}|\$_a\"; done
            printf '%s\n' \"\$_cy_recorded\" > \"\$MARKER\"
        }
        git_worktree_spawn issue-bgempty --launch --bg >/dev/null 2>&1
        cat \"\$MARKER\"
    "
    assert_success
    # 2 args: '--bg' and '' (empty). Pipe delimiter preserves the empty arg.
    assert_output "|--bg|"
}

@test "bash: spawn --launch --bg with task passes the task string through" {
    run_in_bash "
        cd '$FAKE_REPO' || exit 1
        MARKER='$TEST_TEMP_HOME/spawn-bg-task-marker'
        export MARKER
        claude_yolo() {
            local _cy_recorded=''
            for _a in \"\$@\"; do _cy_recorded=\"\${_cy_recorded}|\$_a\"; done
            printf '%s\n' \"\$_cy_recorded\" > \"\$MARKER\"
        }
        git_worktree_spawn issue-bgtask --launch --bg 'fix login flow' >/dev/null 2>&1
        cat \"\$MARKER\"
    "
    assert_success
    # The task string survives shell quoting through eval — 2 args, second
    # carries spaces verbatim.
    assert_output "|--bg|fix login flow"
}

@test "bash: spawn --launch --user work --bg threads account through" {
    # AC-6 path: --user work + --bg → claude_yolo --user work --bg ''.
    # Stand up the work account dir so _claude_resolve_account succeeds.
    run_in_bash "
        mkdir -p '$HOME/.claude-work' '$HOME/.claude-personal'
        # Space-separated whitelist (see claude.sh _claude_resolve_account).
        export CLAUDE_ENABLED_ACCOUNTS='personal work'
        cd '$FAKE_REPO' || exit 1
        MARKER='$TEST_TEMP_HOME/spawn-bg-user-marker'
        export MARKER
        claude_yolo() {
            local _cy_recorded=''
            for _a in \"\$@\"; do _cy_recorded=\"\${_cy_recorded}|\$_a\"; done
            printf '%s\n' \"\$_cy_recorded\" > \"\$MARKER\"
        }
        git_worktree_spawn issue-bgwork --launch --user work --bg >/dev/null 2>&1
        cat \"\$MARKER\"
    "
    assert_success
    # 4 args: '--user', 'work', '--bg', ''
    assert_output "|--user|work|--bg|"
}

@test "bash: spawn without --bg still dispatches plain claude_yolo" {
    # Regression guard: default --launch path must NOT silently grow --bg.
    run_in_bash "
        cd '$FAKE_REPO' || exit 1
        MARKER='$TEST_TEMP_HOME/spawn-no-bg-marker'
        export MARKER
        claude_yolo() {
            local _cy_recorded=''
            for _a in \"\$@\"; do _cy_recorded=\"\${_cy_recorded}|\$_a\"; done
            printf '%s\n' \"[\$_cy_recorded]\" > \"\$MARKER\"
        }
        git_worktree_spawn issue-nobg --launch >/dev/null 2>&1
        cat \"\$MARKER\"
    "
    assert_success
    # Empty arg list — claude_yolo invoked with zero extra args.
    assert_output "[]"
}
