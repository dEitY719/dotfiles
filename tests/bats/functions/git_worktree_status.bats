#!/usr/bin/env bats
# tests/bats/functions/git_worktree_status.bats
# Tests for `gwt ls` (status-aware) and `gwt status` — issue #285.
# Behavior under test:
#   - Verdict matrix produces the expected state for each known signal
#     (dirty, ahead, merged, stale, clean, prunable, locked).
#   - `gwt ls` adds STATE/AGE/NEXT columns by default; `--quick` preserves
#     the legacy path/commit/branch shape; `--remote` is offered as a hint.
#   - `gwt status` mirrors gh-flow status's per-issue diagnostic layout.

load '../test_helper'

# ---------------------------------------------------------------------------
# Fake repo + worktree helpers
# ---------------------------------------------------------------------------

# Build a minimal main repo at $MAIN_REPO with one base commit on `main`.
_setup_main_repo() {
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    MAIN_REPO="$TEST_TEMP_HOME/proj"
    git init -q --initial-branch=main "$MAIN_REPO"
    (
        cd "$MAIN_REPO"
        echo base >base.txt
        git add base.txt
        git commit -q -m base
    )
}

# Add a worktree at $MAIN_REPO/../proj-<name>-1 on a branch wt/<name>/1.
# Args: <name>
_add_worktree() {
    local _name="$1"
    local _path="$TEST_TEMP_HOME/proj-${_name}-1"
    git -C "$MAIN_REPO" worktree add -q -b "wt/${_name}/1" "$_path" main
    printf '%s' "$_path"
}

setup() {
    setup_isolated_home
    _setup_main_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# gwt ls — default (status-aware)
# ---------------------------------------------------------------------------

@test "ls: default shows STATE/AGE/NEXT columns" {
    _add_worktree feature >/dev/null
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "STATE"
    assert_output --partial "AGE"
    assert_output --partial "NEXT"
}

@test "ls: clean main worktree shows 'clean'" {
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "clean"
}

@test "ls: feature branch with no commits ahead shows 'clean'" {
    _add_worktree feature >/dev/null
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "wt/feature/1"
    # No commits beyond main → not 'ahead'.
    refute_output --partial "ahead"
}

@test "ls: dirty worktree (uncommitted changes) shows 'dirty'" {
    local _wt
    _wt=$(_add_worktree dirty)
    echo "modified" >>"$_wt/base.txt"
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "dirty"
    assert_output --partial "commit or stash"
}

@test "ls: ahead worktree (committed but not in main) shows 'ahead'" {
    local _wt
    _wt=$(_add_worktree ahead)
    (
        cd "$_wt"
        echo new >new.txt
        git add new.txt
        git commit -q -m "ahead commit"
    )
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "ahead"
}

@test "ls: --quick preserves legacy output (no STATE column)" {
    _add_worktree feature >/dev/null
    run_in_bash "cd '$MAIN_REPO' && gwt ls --quick"
    assert_success
    assert_output --partial "[path]"
    assert_output --partial "[branch]"
    refute_output --partial "STATE"
    refute_output --partial "NEXT"
}

@test "ls: hint suggests gwt status and --remote" {
    _add_worktree feature >/dev/null
    run_in_bash "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "gwt status"
    assert_output --partial "--remote"
}

@test "ls: --help shows flag descriptions" {
    run_in_bash "cd '$MAIN_REPO' && gwt ls --help"
    assert_success
    assert_output --partial "--quick"
    assert_output --partial "--remote"
}

@test "ls: rejects unknown flag" {
    run_in_bash "cd '$MAIN_REPO' && gwt ls --bogus 2>&1"
    assert_failure
    assert_output --partial "Unknown flag"
}

# ---------------------------------------------------------------------------
# gwt status — single-worktree diagnostic
# ---------------------------------------------------------------------------

@test "status: no arg, in main repo → renders main-repo summary" {
    run_in_bash "cd '$MAIN_REPO' && gwt status"
    assert_success
    assert_output --partial "gwt status"
    assert_output --partial "Path"
    assert_output --partial "Branch"
    assert_output --partial "Verdict"
}

@test "status: no arg, inside a worktree → diagnoses that worktree" {
    local _wt
    _wt=$(_add_worktree feat)
    run_in_bash "cd '$_wt' && gwt status"
    assert_success
    assert_output --partial "wt/feat/1"
    assert_output --partial "Verdict"
    assert_output --partial "Next action"
}

@test "status: <name> from main repo resolves the matching worktree" {
    _add_worktree foo >/dev/null
    run_in_bash "cd '$MAIN_REPO' && gwt status foo"
    assert_success
    assert_output --partial "wt/foo/1"
    assert_output --partial "Verdict"
}

@test "status: <name> from a sibling worktree still resolves correctly" {
    # Issue #285 specifically called out that <name> matching must work from
    # any worktree, not just the main repo. Anchors on git-common-dir.
    _add_worktree alpha >/dev/null
    local _other
    _other=$(_add_worktree beta)
    run_in_bash "cd '$_other' && gwt status alpha"
    assert_success
    assert_output --partial "wt/alpha/1"
}

@test "status: dirty worktree → verdict is 'dirty', next action 'commit or stash'" {
    local _wt
    _wt=$(_add_worktree dirty)
    echo "x" >>"$_wt/base.txt"
    run_in_bash "cd '$MAIN_REPO' && gwt status dirty"
    assert_success
    assert_output --partial "dirty"
    assert_output --partial "commit or stash"
    assert_output --partial "Uncommitted"
}

@test "status: nonexistent name → error with hint" {
    run_in_bash "cd '$MAIN_REPO' && gwt status nonesuch 2>&1"
    assert_failure
    assert_output --partial "no worktree matches"
    assert_output --partial "gwt list"
}

@test "status: --help renders usage" {
    run_in_bash "cd '$MAIN_REPO' && gwt status --help"
    assert_success
    assert_output --partial "Usage: gwt status"
}

# ---------------------------------------------------------------------------
# gwt-help — status section is registered
# ---------------------------------------------------------------------------

@test "help: summary lists the new status subcommand" {
    run_in_bash 'gwt_help'
    assert_success
    assert_output --partial "status: gwt status"
}

@test "help: status section renders rows" {
    run_in_bash 'gwt_help status'
    assert_success
    assert_output --partial "Per-worktree diagnostic"
    assert_output --partial "Mirrors gh-flow status"
}

@test "help: list section mentions --remote and --quick" {
    # Use `ls` (not `list`) — the dispatcher intercepts bare `list` to mean
    # "show section index", whereas `ls` falls through to the section-rows
    # path. Existing behavior, not changed by this issue.
    run_in_bash 'gwt_help ls'
    assert_success
    assert_output --partial "--remote"
    assert_output --partial "--quick"
}

# ---------------------------------------------------------------------------
# zsh parity — sanity check the new entry points exist under zsh
# ---------------------------------------------------------------------------

@test "zsh: git_worktree_status function exists" {
    run_in_zsh 'declare -f git_worktree_status >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gwt ls runs without errors on a clean main repo" {
    run_in_zsh "cd '$MAIN_REPO' && gwt ls"
    assert_success
    assert_output --partial "STATE"
}
