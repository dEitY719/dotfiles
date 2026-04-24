#!/usr/bin/env bats
# tests/bats/functions/gh_flow.bats
# Unit tests for gh_flow subcommands, post-condition helpers, and the
# _gh_flow_set_project_status board-sync helper. The worker pipeline itself
# (Step 2: implement → commit → pr) is not exercised here — it needs claude /
# gh / gwt and is covered by manual integration testing.

load '../test_helper'

# ---------------------------------------------------------------------------
# Fake repo + state directory helpers
# ---------------------------------------------------------------------------

# Build a minimal git repo at $HOME/repo and cd there via $REPO_DIR. We need
# an actual repo because _gh_flow_repo_name / _gh_flow_state_root key off
# `git rev-parse --show-toplevel`.
_setup_fake_repo() {
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
    REPO_DIR="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO_DIR"
    git -C "$REPO_DIR" init --initial-branch=main -q
    echo base >"$REPO_DIR/base.txt"
    git -C "$REPO_DIR" add base.txt
    git -C "$REPO_DIR" commit -q -m "base"
}

# Seed one gh_flow state dir. Args: <issue> <state> [worktree_path] [pid]
_seed_state() {
    local _issue="$1" _state="$2" _wt="${3:-}" _pid="${4:-}"
    local _dir="$HOME/.local/state/gh-flow/repo/$_issue"
    mkdir -p "$_dir"
    printf '%s\n' "$_state" >"$_dir/state"
    if [ -n "$_wt" ]; then printf '%s\n' "$_wt" >"$_dir/worktree.path"; fi
    if [ -n "$_pid" ]; then printf '%s\n' "$_pid" >"$_dir/pid"; fi
    return 0
}

setup() {
    setup_isolated_home
    _setup_fake_repo
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# help output
# ---------------------------------------------------------------------------

@test "help: mentions new status and prune subcommands" {
    run_in_bash "gh_flow --help"
    assert_success
    assert_output --partial "gh-flow status"
    assert_output --partial "gh-flow prune"
    # New distinct failure states must be documented.
    assert_output --partial "failed:committing"
    assert_output --partial "failed:opening-pr"
}

# ---------------------------------------------------------------------------
# gh_flow status
# ---------------------------------------------------------------------------

@test "status: empty repo — prints 'no state' and exits 0" {
    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "no state"
}

@test "status: lists each seeded entry with its state" {
    _seed_state 13 "polling" "" "99999"
    _seed_state 42 "failed:committing" "$TEST_TEMP_HOME/repo-issue-42-1" "12345"
    _seed_state 88 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#13"
    assert_output --partial "polling"
    assert_output --partial "#42"
    assert_output --partial "failed:committing"
    assert_output --partial "repo-issue-42-1"
    assert_output --partial "#88"
    assert_output --partial "done"
}

@test "status: pid liveness — current shell pid shown as alive" {
    _seed_state 77 "polling" "" "$$"

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#77"
    assert_output --partial "polling"
    # $$ from the bats shell is definitely alive while this test runs.
    assert_output --partial "alive"
}

@test "status: pid liveness — unreachable pid shown as dead" {
    # PID 1 is init — reachable by root but not by us. Fine for 'dead' check
    # only if we're non-root; most CI runs are non-root, but to be safe use an
    # unlikely huge pid.
    _seed_state 55 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-55-1" "9999999"

    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    assert_output --partial "#55"
    assert_output --partial "dead"
}

# ---------------------------------------------------------------------------
# gh_flow prune
# ---------------------------------------------------------------------------

@test "prune: removes 'done' state dirs and keeps 'failed:*' ones" {
    _seed_state 10 "done" "" ""
    _seed_state 20 "failed:implementing" "$TEST_TEMP_HOME/repo-issue-20-1" "12345"
    _seed_state 30 "done" "" ""

    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "#10"
    assert_output --partial "#30"
    assert_output --partial "#20"
    assert_output --partial "failed:implementing"

    # Done dirs gone.
    [ ! -d "$HOME/.local/state/gh-flow/repo/10" ]
    [ ! -d "$HOME/.local/state/gh-flow/repo/30" ]
    # Failed dir preserved.
    [ -d "$HOME/.local/state/gh-flow/repo/20" ]
}

@test "prune: failed entry shows the gwt teardown hint when worktree exists" {
    mkdir -p "$TEST_TEMP_HOME/repo-issue-42-1"
    _seed_state 42 "failed:opening-pr" "$TEST_TEMP_HOME/repo-issue-42-1" "12345"

    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "repo-issue-42-1"
    assert_output --partial "gwt teardown"
}

@test "prune: empty state tree — 'nothing to prune' and exits 0" {
    run_in_bash "cd '$REPO_DIR' && gh_flow prune"
    assert_success
    assert_output --partial "nothing to prune"
}

@test "prune: rejects unknown flags" {
    run_in_bash "cd '$REPO_DIR' && gh_flow prune --bogus 2>&1"
    assert_failure
    assert_output --partial "unknown arg"
}

# ---------------------------------------------------------------------------
# dispatcher: subcommand vs integer
# ---------------------------------------------------------------------------

@test "dispatcher: 'status' is not parsed as an invalid issue number" {
    # Regression: early code validated every arg as a positive integer before
    # dispatching subcommands. 'status' would trigger the integer-validation
    # error path.
    run_in_bash "cd '$REPO_DIR' && gh_flow status"
    assert_success
    refute_output --partial "invalid issue number"
}

@test "dispatcher: garbage arg still errors with a useful hint" {
    run_in_bash "cd '$REPO_DIR' && gh_flow not-a-number 2>&1"
    assert_failure
    assert_output --partial "invalid issue number"
    # The error should point users to the subcommands.
    assert_output --partial "status"
    assert_output --partial "prune"
}

# ---------------------------------------------------------------------------
# post-condition helpers (the ones the worker uses between Step 2 sub-steps)
# ---------------------------------------------------------------------------

@test "helper: has_work_for_commit — true when tree has uncommitted changes" {
    echo new >"$REPO_DIR/new.txt"
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_work_for_commit && echo YES || echo NO"
    assert_success
    assert_output --partial "YES"
}

@test "helper: has_work_for_commit — false on clean tree" {
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_work_for_commit && echo YES || echo NO"
    assert_success
    assert_output --partial "NO"
}

@test "helper: has_branch_commits — false when HEAD == origin/main base" {
    # This fake repo has no 'origin' remote; helper falls back to 'origin/main'
    # which also doesn't exist — git rev-list errors → count=0 → false.
    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_branch_commits && echo YES || echo NO"
    assert_success
    assert_output --partial "NO"
}

@test "helper: has_branch_commits — true when branch has commits ahead of origin/HEAD" {
    # Build a real origin so rev-list has something to compare against.
    local origin="$TEST_TEMP_HOME/origin.git"
    git init --bare --initial-branch=main -q "$origin"
    git -C "$REPO_DIR" remote add origin "$origin"
    git -C "$REPO_DIR" push -q origin main
    git -C "$REPO_DIR" remote set-head origin main >/dev/null 2>&1 || true

    # Add one more commit on main — it's now ahead of origin/main.
    echo extra >"$REPO_DIR/extra.txt"
    git -C "$REPO_DIR" add extra.txt
    git -C "$REPO_DIR" commit -q -m "extra"

    run_in_bash "cd '$REPO_DIR' && _gh_flow_has_branch_commits && echo YES || echo NO"
    assert_success
    assert_output --partial "YES"
}

# ---------------------------------------------------------------------------
# _gh_flow_set_project_status — loading and guard paths (no network required)
# ---------------------------------------------------------------------------

@test "bash: _gh_flow_set_project_status helper exists" {
    run_in_bash 'declare -f _gh_flow_set_project_status >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_flow_set_project_status helper exists" {
    run_in_zsh 'typeset -f _gh_flow_set_project_status >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "project-status: opt-out via GH_FLOW_PROJECT_STATUS_SYNC=0 returns silently" {
    run_in_bash 'GH_FLOW_PROJECT_STATUS_SYNC=0 _gh_flow_set_project_status issue 1 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "project-status:"
}

@test "project-status: missing args returns silently" {
    run_in_bash '_gh_flow_set_project_status 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "project-status:"
}

@test "project-status: invalid kind returns 0 with warning" {
    run_in_bash '_gh_flow_set_project_status bogus 42 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "invalid kind=bogus"
}
