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

# ---------------------------------------------------------------------------
# D/E/F: merge target = origin/main + actionable unpushed msg + quiet checkout
# ---------------------------------------------------------------------------

# Simulate a squash-merge of the worktree branch into origin/main.
# After this: origin/main contains the worktree's change under a different SHA.
_squash_merge_branch_into_origin_main() {
    # Record the worktree's work commit tree contents
    local wt_file wt_content
    wt_file="$1"
    wt_content="$2"

    local helper="$TEST_TEMP_HOME/squash-helper"
    rm -rf "$helper"
    git clone -q "$ORIGIN" "$helper"
    (
        cd "$helper"
        # Apply the same change as a single commit (squash equivalent)
        printf '%s\n' "$wt_content" > "$wt_file"
        git add "$wt_file"
        git commit -q -m "squash: merged via PR"
        git push -q origin main
    )
    rm -rf "$helper"
    git -C "$CLONE" fetch -q origin
}

@test "teardown: D — rebase-merged detection uses origin/main even when local main stale" {
    # 1. Worktree makes a commit with content X
    (
        cd "$WORKTREE"
        echo contentX > feature.txt
        git add feature.txt
        git commit -q -m "feat: X"
    )
    # 2. Simulate PR squash-merge: origin/main gets X under a new SHA
    _squash_merge_branch_into_origin_main feature.txt contentX

    # 3. Make LOCAL main diverge so ff-only fails — _gwt_branch_merged will be
    #    called with a stale local main. Without D fix, it compares patches
    #    against the stale local main (which lacks X) and misses the merge.
    _diverge_local_main

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>&1"
    # Main sync fails (local diverged) so exit 1 per C-2. But branch delete
    # should still announce "rebase-merged" because origin/main contains the
    # branch's patches.
    assert_failure
    assert_output --partial "rebase-merged"
    refute_output --partial "force-deleted"
    refute_output --partial "not fully merged"
}

@test "teardown: E — unpushed-commits error shows ahead count and push hint" {
    # Worktree branch is ahead of origin/main but never pushed. No --force.
    (
        cd "$WORKTREE"
        echo a > a.txt && git add a.txt && git commit -q -m "a"
        echo b > b.txt && git add b.txt && git commit -q -m "b"
        echo c > c.txt && git add c.txt && git commit -q -m "c"
    )

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>&1"
    assert_failure
    # Must show how many commits are unpushed
    assert_output --partial "3"
    # Must suggest an actual push command the user can run
    assert_output --partial "git push"
    assert_output --partial "wt/test/1"
    # And still mention --force as the alternative
    assert_output --partial "--force"
}

@test "teardown: F — git checkout stdout noise ('Your branch is behind') suppressed" {
    # Make local main behind origin/main. git checkout main would normally print
    # "Your branch is behind 'origin/main' by 1 commits, and can be fast-forwarded."
    # to stdout (unsilenceable by 2>/dev/null). With `checkout -q` it's gone.
    _advance_origin_main

    run_in_bash "cd '$WORKTREE' && gwt teardown --force 2>&1"
    assert_success
    refute_output --partial "Your branch is behind"
    refute_output --partial "use \"git pull\""
}

# ---------------------------------------------------------------------------
# Issue #195: untracked-files pre-flight, stderr surfacing, cwd-on-failure
# ---------------------------------------------------------------------------

@test "teardown: untracked files block teardown with actionable guidance (no --force)" {
    # Put an untracked file inside the worktree — git worktree remove would
    # refuse with a swallowed stderr. The new pre-flight should catch it.
    printf 'stray\n' > "$WORKTREE/.DS_Store"

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>&1"
    assert_failure
    assert_output --partial "Untracked files present"
    # Actionable next-steps surface the three commands from the issue spec.
    assert_output --partial "git status --short"
    assert_output --partial "git clean -fd"
    assert_output --partial "gwt teardown --force"
    # Worktree and branch still exist — we refused cleanly.
    [ -d "$WORKTREE" ]
    run git -C "$CLONE" rev-parse --verify --quiet wt/test/1
    assert_success
}

@test "teardown: untracked files pass with --force and worktree is removed" {
    printf 'stray\n' > "$WORKTREE/.DS_Store"

    run_in_bash "cd '$WORKTREE' && gwt teardown --force 2>&1"
    assert_success
    # Worktree directory is gone and branch deleted.
    [ ! -d "$WORKTREE" ]
    run git -C "$CLONE" rev-parse --verify --quiet wt/test/1
    assert_failure
}

@test "teardown: failed remove surfaces git stderr + path (not just 'use --force')" {
    # Force the `git worktree remove` step to fail with a git-reported reason
    # by locking the worktree. The pre-flights pass (no dirty/untracked/
    # unpushed), so control reaches the remove call. Without the fix, stderr
    # is swallowed and the user sees only "Cannot remove worktree...".
    git -C "$CLONE" worktree lock --reason "held for test" "$WORKTREE"

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>&1"
    assert_failure
    # Path appears so the user knows WHICH worktree failed.
    assert_output --partial "$WORKTREE"
    # git's own reason is surfaced under a "git says:" header, not silenced.
    assert_output --partial "git says:"
    assert_output --partial "locked"
    # Next-action hints still render.
    assert_output --partial "Override: gwt teardown --force"

    # Cleanup: unlock so teardown doesn't leave the temp tree poisoned.
    git -C "$CLONE" worktree unlock "$WORKTREE" 2>/dev/null || true
}

@test "teardown: on failure, cwd stays in the worktree (not main repo)" {
    # Same locked-worktree scenario as above. After teardown fails, the shell
    # should still be inside $WORKTREE so the user can `git status` without
    # having to cd back. Verify by echoing pwd from inside the same subshell
    # after the failing call.
    git -C "$CLONE" worktree lock --reason "held for test" "$WORKTREE"

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>/dev/null; printf 'CWD=%s\n' \"\$(pwd)\""
    # Function returned non-zero but we chained with ; so the subshell exits 0.
    assert_output --partial "CWD=$WORKTREE"

    git -C "$CLONE" worktree unlock "$WORKTREE" 2>/dev/null || true
}
