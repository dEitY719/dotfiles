#!/usr/bin/env bats
# tests/bats/functions/gh_pr_approve.bats
# Smoke tests for the gh-pr-approve orchestrator. These cover the
# pre-spawn surface (loading, help, arg validation) — the detached-worker
# pipeline is not exercised here because it would require mocking gwt,
# gh, and claude inside a subshell. That's consistent with how gh-flow
# (the sibling feature) is tested today.

load '../test_helper'

# Spin up a throwaway main repo so arg-validation tests don't trip the
# "must run from main repo" precondition check — the bats host repo is
# itself a worktree, which would short-circuit the validator.
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

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "bash: gh_pr_approve function exists" {
    run_in_bash 'declare -f gh_pr_approve >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-pr-approve alias resolves to gh_pr_approve" {
    run_in_bash "alias gh-pr-approve 2>/dev/null | grep -q gh_pr_approve && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_pr_approve function exists" {
    run_in_zsh 'typeset -f gh_pr_approve >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Help surface (bypasses all preconditions)
# ---------------------------------------------------------------------------

@test "bash: gh-pr-approve with no args prints help" {
    run_in_bash 'gh_pr_approve'
    assert_success
    assert_output --partial "gh-pr-approve"
    assert_output --partial "pr-number"
}

@test "bash: gh-pr-approve --help prints help" {
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gh-pr-approve"
}

@test "bash: gh-pr-approve -h prints help" {
    run_in_bash 'gh_pr_approve -h'
    assert_success
}

@test "bash: help documents parallel usage and state dir" {
    # The help must describe the two things that distinguish this from
    # running /gh-pr-approve manually: parallelism and the state dir.
    # If either is missing, users lose the discoverability the feature
    # was designed around.
    run_in_bash 'gh_pr_approve --help 2>&1'
    assert_success
    assert_output --partial "parallel"
    assert_output --partial "state"
}

# ---------------------------------------------------------------------------
# Argument validation — must fail before any spawn attempt
# ---------------------------------------------------------------------------

@test "bash: non-integer PR number is rejected" {
    # 'abc' is obviously not a PR number. The function must reject it
    # rather than hand it to gwt and produce a confusing failure later.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve abc 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: mixed valid + invalid args reject the batch" {
    # Fail-fast: one bad arg in the list aborts the whole batch. This
    # matches gh-flow's behavior and prevents half-spawned state.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 notanumber 2>&1"
    assert_failure
    assert_output --partial "invalid"
}

@test "bash: '#' prefix on PR number is accepted (ergonomic)" {
    # Ergonomic deviation from gh-flow (which requires pure integers).
    # PR numbers are written as #N in conversation, so both forms work.
    # We can't run the worker in tests, but we can at least prove the
    # validator accepts '#42' — the error, if any, must come later than
    # the 'invalid PR number' check.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve '#42' 2>&1 || true"
    refute_output --partial "invalid PR number"
}

@test "bash: rejects run from inside a worktree" {
    # The orchestrator must refuse to spawn from a worktree — workers
    # would otherwise create worktrees-of-worktrees, which gwt doesn't
    # support. This is the same guard gh-flow enforces.
    (
        cd "$FAKE_REPO"
        git worktree add -q -b test-wt "$TEST_TEMP_HOME/fake-wt" 2>/dev/null
    )
    run_in_bash "cd '$TEST_TEMP_HOME/fake-wt' && gh_pr_approve 42 2>&1"
    assert_failure
    assert_output --partial "main repo"
}

# ---------------------------------------------------------------------------
# --ai option (mirrors gh-flow #208 contract)
# ---------------------------------------------------------------------------

@test "help: documents --ai option and supported runners" {
    # The whole point of #214 is discoverability — if --ai isn't surfaced
    # in help, users will keep assuming claude is the only option.
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "--ai"
    assert_output --partial "claude (default) | codex | gemini"
}

@test "help: documents self-PR modes" {
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "--self-record"
    assert_output --partial "--admin-merge"
}

@test "bash: '--ai codex' parses (precondition fails on missing codex CLI, not parser)" {
    # We can't easily fake the codex/gemini CLI here, so we assert the
    # parser accepted the value and produced a precondition-shaped error
    # rather than the generic 'unknown option' or 'invalid --ai value'
    # parser errors.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai codex 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid --ai value"
}

@test "bash: '--ai gemini' parses with leading position" {
    # --ai may appear before PR numbers — position-agnostic.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve --ai gemini 42 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid --ai value"
    refute_output --partial "invalid PR number"
}

@test "bash: trailing '42 --ai codex' is accepted" {
    # Regression guard: --ai after PR numbers must be parsed, not
    # treated as a stray PR number.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai codex 2>&1 || true"
    refute_output --partial "invalid PR number: '--ai'"
}

@test "bash: '--ai' without value fails with clear message" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai 2>&1"
    assert_failure
    assert_output --partial "missing value for --ai"
    assert_output --partial "claude|codex|gemini"
}

@test "bash: invalid --ai value is rejected" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --ai bogus 2>&1"
    assert_failure
    assert_output --partial "invalid --ai value"
    assert_output --partial "claude|codex|gemini"
}

@test "bash: unknown long option is rejected" {
    # Anything starting with '-' that isn't --ai/--ai=... should be
    # rejected up-front rather than reaching the PR-number validator.
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve --bogus 42 2>&1"
    assert_failure
    assert_output --partial "unknown option"
}

# ---------------------------------------------------------------------------
# self-PR options
# ---------------------------------------------------------------------------

@test "bash: legacy --self-ok is rejected with server-side guidance" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --self-ok 2>&1"
    assert_failure
    assert_output --partial "--self-ok is not supported"
    assert_output --partial "server-side"
}

@test "bash: '--self-record' parses as a self-PR mode" {
    run_in_bash "cd '$FAKE_REPO' && PATH=/nonexistent gh_pr_approve 42 --self-record 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid PR number"
}

@test "bash: '--admin-merge --squash' parses as a self-PR mode" {
    run_in_bash "cd '$FAKE_REPO' && PATH=/nonexistent gh_pr_approve 42 --admin-merge --squash 2>&1 || true"
    refute_output --partial "unknown option"
    refute_output --partial "invalid PR number"
}

@test "bash: merge strategy flags require --admin-merge" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve 42 --squash 2>&1"
    assert_failure
    assert_output --partial "--squash requires --admin-merge"
}

# ---------------------------------------------------------------------------
# status / prune subcommands (issue #268)
# ---------------------------------------------------------------------------

# Seed one gh_pr_approve state dir. Args: <pr> <state> [worktree] [pid] [flags]
_seed_pr_state() {
    local _pr="$1" _state="$2" _wt="${3:-}" _pid="${4:-}" _flags="${5:-}"
    local _dir="$HOME/.local/state/gh-pr-approve/fake-main/$_pr"
    mkdir -p "$_dir"
    printf '%s\n' "$_state" >"$_dir/state"
    if [ -n "$_wt" ]; then printf '%s\n' "$_wt" >"$_dir/worktree.path"; fi
    if [ -n "$_pid" ]; then printf '%s\n' "$_pid" >"$_dir/pid"; fi
    if [ -n "$_flags" ]; then printf '%s\n' "$_flags" >"$_dir/flags"; fi
    return 0
}

@test "help: documents status and prune subcommands" {
    run_in_bash 'gh_pr_approve --help'
    assert_success
    assert_output --partial "gh-pr-approve status"
    assert_output --partial "gh-pr-approve prune"
    assert_output --partial "failed:spawning"
    assert_output --partial "failed:approving"
    assert_output --partial "failed:tearing-down"
    assert_output --partial "flags"
}

@test "status: empty repo — prints 'no state' and exits 0" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status"
    assert_success
    assert_output --partial "no state"
}

@test "status: lists each seeded entry with its state" {
    _seed_pr_state 13 "approving" "" "99999"
    _seed_pr_state 42 "failed:approving" "$TEST_TEMP_HOME/pr-42-wt" "12345"
    _seed_pr_state 88 "done" "" ""

    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status"
    assert_success
    assert_output --partial "#13"
    assert_output --partial "approving"
    assert_output --partial "#42"
    assert_output --partial "failed:approving"
    assert_output --partial "pr-42-wt"
    assert_output --partial "#88"
    assert_output --partial "done"
}

@test "status: pid liveness — current shell pid shown as alive" {
    _seed_pr_state 77 "approving" "" "$$"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status"
    assert_success
    assert_output --partial "#77"
    assert_output --partial "alive"
}

@test "status: pid liveness — unreachable pid shown as dead" {
    _seed_pr_state 55 "failed:approving" "$TEST_TEMP_HOME/pr-55-wt" "9999999"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status"
    assert_success
    assert_output --partial "#55"
    assert_output --partial "dead"
}

# ---------------------------------------------------------------------------
# verdict matrix
# ---------------------------------------------------------------------------

@test "verdict: done → 'safe to prune' + scoped prune action" {
    _seed_pr_state 100 "done" "" ""
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 100"
    assert_success
    assert_line --index 0 "done — safe to prune"
    assert_line --index 1 "gh-pr-approve prune 100"
}

@test "verdict: approving + alive pid → active worker, leave alone" {
    _seed_pr_state 201 "approving" "" "$$"
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 201"
    assert_success
    assert_output --partial "active worker (approving)"
    assert_output --partial "still working"
}

@test "verdict: approving + dead pid → dead worker mid-step" {
    _seed_pr_state 202 "approving" "" "9999999"
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 202"
    assert_success
    assert_output --partial "dead worker mid-step (approving)"
    assert_output --partial "gh-pr-approve prune 202"
}

@test "verdict: failed:* + worktree absent → state-only cleanup" {
    _seed_pr_state 301 "failed:approving" "" "12345"
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 301"
    assert_success
    assert_output --partial "dead failure"
    assert_output --partial "gh-pr-approve prune 301"
}

@test "verdict: failed:* + worktree present → gwt teardown first" {
    mkdir -p "$TEST_TEMP_HOME/pr-302-wt"
    _seed_pr_state 302 "failed:tearing-down" "$TEST_TEMP_HOME/pr-302-wt" "12345"
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 302"
    assert_success
    assert_output --partial "worktree alive"
    assert_output --partial "gwt teardown --force"
}

@test "verdict: missing dir → 'no state — PR not tracked'" {
    run_in_bash "cd '$FAKE_REPO' && _gh_pr_approve_verdict 999"
    assert_success
    assert_line --index 0 "no state — PR not tracked"
    assert_line --index 1 "(none)"
}

# ---------------------------------------------------------------------------
# full-scan prune
# ---------------------------------------------------------------------------

@test "prune: removes 'done' state dirs and keeps 'failed:*' ones" {
    _seed_pr_state 10 "done" "" ""
    _seed_pr_state 20 "failed:approving" "$TEST_TEMP_HOME/pr-20-wt" "12345"
    _seed_pr_state 30 "done" "" ""

    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune"
    assert_success
    assert_output --partial "#10"
    assert_output --partial "#30"
    assert_output --partial "#20"
    assert_output --partial "failed:approving"

    [ ! -d "$HOME/.local/state/gh-pr-approve/fake-main/10" ]
    [ ! -d "$HOME/.local/state/gh-pr-approve/fake-main/30" ]
    [ -d "$HOME/.local/state/gh-pr-approve/fake-main/20" ]
}

@test "prune: failed entry shows the gwt teardown hint when worktree exists" {
    mkdir -p "$TEST_TEMP_HOME/pr-42-wt"
    _seed_pr_state 42 "failed:approving" "$TEST_TEMP_HOME/pr-42-wt" "12345"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune"
    assert_success
    assert_output --partial "pr-42-wt"
    assert_output --partial "gwt teardown"
}

@test "prune: empty state tree — 'nothing to prune' and exits 0" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune"
    assert_success
    assert_output --partial "nothing to prune"
}

@test "prune: rejects unknown flags" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune --bogus 2>&1"
    assert_failure
    assert_output --partial "unknown arg"
}

# ---------------------------------------------------------------------------
# scoped prune
# ---------------------------------------------------------------------------

@test "prune <N>: rejects when worker pid is alive" {
    _seed_pr_state 401 "approving" "" "$$"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune 401 2>&1"
    assert_failure
    assert_output --partial "#401"
    assert_output --partial "still alive"
    assert_output --partial "--force"
    [ -d "$HOME/.local/state/gh-pr-approve/fake-main/401" ]
}

@test "prune <N>: rejects when worktree dir is present" {
    mkdir -p "$TEST_TEMP_HOME/pr-402-wt"
    _seed_pr_state 402 "failed:approving" "$TEST_TEMP_HOME/pr-402-wt" "9999999"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune 402 2>&1"
    assert_failure
    assert_output --partial "#402"
    assert_output --partial "worktree exists"
    assert_output --partial "gwt teardown --force"
    [ -d "$HOME/.local/state/gh-pr-approve/fake-main/402" ]
}

@test "prune --force <N>: still rejects when worktree dir is present" {
    mkdir -p "$TEST_TEMP_HOME/pr-403-wt"
    _seed_pr_state 403 "failed:approving" "$TEST_TEMP_HOME/pr-403-wt" "9999999"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune --force 403 2>&1"
    assert_failure
    assert_output --partial "worktree exists"
    [ -d "$HOME/.local/state/gh-pr-approve/fake-main/403" ]
}

@test "prune --force <N>: kills alive pid and removes state dir" {
    sleep 60 &
    local _victim=$!
    _seed_pr_state 404 "approving" "" "$_victim"

    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune --force 404"
    assert_success
    [ ! -d "$HOME/.local/state/gh-pr-approve/fake-main/404" ]
    run kill -0 "$_victim" 2>/dev/null
    assert_failure
    wait "$_victim" 2>/dev/null || true
}

@test "prune <N>: accepts '#N' form (strips leading #)" {
    _seed_pr_state 405 "done" "" ""
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune '#405'"
    assert_success
    [ ! -d "$HOME/.local/state/gh-pr-approve/fake-main/405" ]
}

@test "prune <N>: rejects non-integer PR arg" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune abc 2>&1"
    assert_failure
    assert_output --partial "invalid PR number"
}

# ---------------------------------------------------------------------------
# per-PR status (issue #268 — flags display, full table)
# ---------------------------------------------------------------------------

@test "status <N>: prints header + Verdict + Next action" {
    _seed_pr_state 501 "done" "" ""
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status 501"
    assert_success
    assert_output --partial "gh-pr-approve status #501"
    assert_output --partial "State"
    assert_output --partial "done"
    assert_output --partial "Verdict"
    assert_output --partial "Next action"
}

@test "status <N>: '#N' form also accepted" {
    _seed_pr_state 502 "done" "" ""
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status '#502'"
    assert_success
    assert_output --partial "#502"
}

@test "status <N>: missing state dir → warning, exits 0" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status 503"
    assert_success
    assert_output --partial "no state for #503"
}

@test "status <N>: rejects multiple positional args" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status 504 505 2>&1"
    assert_failure
    assert_output --partial "only one PR number"
}

@test "status <N>: shows recorded flags" {
    _seed_pr_state 506 "approving" "" "$$" "--admin-merge --squash"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status 506"
    assert_success
    assert_output --partial "Flags"
    assert_output --partial "--admin-merge --squash"
}

@test "status <N>: missing flags file → '(none)'" {
    _seed_pr_state 507 "approving" "" "$$"
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status 507"
    assert_success
    assert_output --partial "Flags"
    assert_output --partial "(none)"
}

# ---------------------------------------------------------------------------
# dispatcher: 'status' / 'prune' must not be parsed as a PR number
# ---------------------------------------------------------------------------

@test "dispatcher: 'status' is not parsed as an invalid PR number" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve status"
    assert_success
    refute_output --partial "invalid PR number"
}

@test "dispatcher: 'prune' is not parsed as an invalid PR number" {
    run_in_bash "cd '$FAKE_REPO' && gh_pr_approve prune"
    assert_success
    refute_output --partial "invalid PR number"
}
