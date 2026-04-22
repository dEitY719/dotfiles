#!/usr/bin/env bats
# tests/bats/functions/git_worktree_teardown.bats
# Real-workflow tests for `gwt teardown` against a fake origin + clone + worktree.
# Each test builds a bare remote and a local clone with a worktree branch,
# simulates the scenario, runs the function via run_in_bash, and asserts on
# both the command result and post-state (refs, branch existence).

load '../test_helper'

# ---------------------------------------------------------------------------
# Fake-repo helpers (run in the bats shell, NOT the run_in_bash subshell)
# ---------------------------------------------------------------------------

# Create: $ORIGIN (bare) <- $CLONE (main) -- $WORKTREE (wt/test/1)
_setup_fake_repo() {
    ORIGIN="$TEST_TEMP_HOME/origin.git"
    CLONE="$TEST_TEMP_HOME/clone"
    WORKTREE="$TEST_TEMP_HOME/clone-test-1"

    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

    git init --bare --initial-branch=main "$ORIGIN" >/dev/null
    git clone -q "$ORIGIN" "$CLONE"
    (
        cd "$CLONE"
        echo base > base.txt
        git add base.txt
        git commit -q -m "base"
        git push -q origin main
    )
    git -C "$CLONE" worktree add -q -b wt/test/1 "$WORKTREE" origin/main
}

# Advance origin/main by one commit (simulates a merged PR).
_advance_origin_main() {
    local helper="$TEST_TEMP_HOME/helper"
    rm -rf "$helper"
    git clone -q "$ORIGIN" "$helper"
    (
        cd "$helper"
        echo advance > advance.txt
        git add advance.txt
        git commit -q -m "advance"
        git push -q origin main
    )
    rm -rf "$helper"
    git -C "$CLONE" fetch -q origin
}

# Make clone's local main diverge from origin/main with a local-only commit.
_diverge_local_main() {
    (
        cd "$CLONE"
        git checkout -q main
        echo divergence > divergence.txt
        git add divergence.txt
        git commit -q -m "local-only"
        git checkout -q wt/test/1 2>/dev/null || true
    )
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
# A/B/C: diagnosability + ff-only sync + strict exit on main-out-of-sync
# ---------------------------------------------------------------------------

@test "teardown: clean merged branch — ff-forwards local main to origin/main" {
    # Simulate: branch was merged into origin/main (HEAD of worktree is the base,
    # origin/main advanced ahead). Running teardown should succeed AND fast-forward
    # the clone's local main to origin/main.
    _advance_origin_main
    local origin_main_sha
    origin_main_sha="$(git -C "$CLONE" rev-parse origin/main)"

    run_in_bash "cd '$WORKTREE' && gwt teardown --force"
    assert_success

    # B: local main advanced to origin/main (via merge --ff-only)
    local after_main_sha
    after_main_sha="$(git -C "$CLONE" rev-parse main)"
    [ "$after_main_sha" = "$origin_main_sha" ]

    # Branch removed
    run git -C "$CLONE" rev-parse --verify --quiet wt/test/1
    assert_failure
}

@test "teardown: diverged local main — strict exit 1 (C-2) with actionable error" {
    # Local main has a commit not in origin/main. fetch --ff-only cannot succeed.
    # Teardown must exit non-zero and explain why.
    _diverge_local_main
    _advance_origin_main

    run_in_bash "cd '$WORKTREE' && gwt teardown --force"
    assert_failure
    # Must mention the actual failing command, not a misleading "network?"
    assert_output --partial "ff-only"
    refute_output --partial "network?"
}

@test "teardown: fetch failure surfaces real stderr (A), not 'network?'" {
    # Point origin at a non-existent path so `git fetch origin` fails at step 1.
    git -C "$CLONE" remote set-url origin "$TEST_TEMP_HOME/does-not-exist.git"

    run_in_bash "cd '$WORKTREE' && gwt teardown --force 2>&1"
    # The error output must include something from git itself (e.g. 'does-not-exist'
    # or 'not a git repository' or 'could not read'), and must NOT reduce the
    # problem to a bare 'network?' blurb.
    refute_output --partial "Fetch failed (network?)"
    assert_output --partial "does-not-exist"
}

@test "teardown: no second network round-trip (B) — works after remote is gone" {
    # Advance origin/main, fetch once (teardown's own fetch does this), THEN
    # break the remote. If teardown tried a second fetch/pull it would fail.
    # With merge --ff-only against already-fetched origin/main it must still succeed.
    _advance_origin_main

    # Pre-fetch so origin/main is populated. Then remove the remote on disk.
    git -C "$CLONE" fetch -q origin
    rm -rf "$ORIGIN"

    local origin_main_sha
    origin_main_sha="$(git -C "$CLONE" rev-parse origin/main)"

    # Teardown's own `git fetch` will now fail (that's Bug A — it should report,
    # not silently eat it). It must still proceed to ff-only which works locally.
    run_in_bash "cd '$WORKTREE' && gwt teardown --force 2>&1"
    assert_success

    local after_main_sha
    after_main_sha="$(git -C "$CLONE" rev-parse main)"
    [ "$after_main_sha" = "$origin_main_sha" ]
}
