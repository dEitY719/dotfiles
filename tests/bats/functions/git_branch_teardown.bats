#!/usr/bin/env bats
# tests/bats/functions/git_branch_teardown.bats
# Regression tests for `gbr teardown` against a fake origin + clone on a
# feature branch (NOT a worktree — gbr is the in-place self-cleanup variant).
#
# Issue #879: `gbr teardown --force` stalled on a merge-conflict / unmerged
# index because the actual `git checkout main` was a plain checkout (no -f),
# which always refuses an unmerged index, and its real stderr was swallowed by
# `2>/dev/null`. The fix:
#   1. detect the unmerged index up front and show actionable guidance,
#   2. keep plain --force NON-destructive (never overwrites local files),
#   3. add an explicit destructive --discard-changes flag,
#   4. surface git's stderr instead of swallowing it.

load '../test_helper'

# Create: $ORIGIN (bare) <- $CLONE (on feat/x with an unresolved merge conflict)
_setup_conflicted_clone() {
    ORIGIN="$TEST_TEMP_HOME/origin.git"
    CLONE="$TEST_TEMP_HOME/clone"

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

        # main advances conflict.txt one way...
        echo mainside > conflict.txt
        git add conflict.txt
        git commit -q -m "main: conflict.txt=mainside"

        # ...feature branch advances it another way, from the common base.
        git checkout -q -b feat/x HEAD~1
        echo featureside > conflict.txt
        git add conflict.txt
        git commit -q -m "feat: conflict.txt=featureside"

        # Merge main → produces an unmerged index (UU conflict.txt), left as-is.
        git merge main >/dev/null 2>&1 || true
    )
}

setup() {
    setup_isolated_home
    _setup_conflicted_clone
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

@test "teardown: unmerged index blocks (no --force) with actionable guidance" {
    # Sanity: we really are in a conflicted/unmerged state.
    run git -C "$CLONE" ls-files --unmerged
    assert_output --partial "conflict.txt"

    run_in_bash "cd '$CLONE' && gbr teardown 2>&1"
    assert_failure
    # Failure reason is explicit (AC #1) — not a bare "Failed to checkout main".
    assert_output --partial "unmerged"
    assert_output --partial "resolve your current index first"
    # Actionable next steps.
    assert_output --partial "git merge --abort"
    assert_output --partial "git stash"
    assert_output --partial "gbr teardown --discard-changes"

    # Non-destructive: the conflicted file content is untouched, branch intact.
    [ "$(git -C "$CLONE" symbolic-ref --short HEAD)" = "feat/x" ]
}

@test "teardown --force does NOT bypass an unmerged index (non-destructive)" {
    # The core #879 bug: --force changed only the warning text, then stalled at
    # the plain checkout. Now --force is explicitly non-destructive here.
    run_in_bash "cd '$CLONE' && gbr teardown --force 2>&1"
    assert_failure
    assert_output --partial "Plain --force does NOT bypass"
    assert_output --partial "gbr teardown --discard-changes"

    # Still on the feature branch; conflicted file not destroyed (AC #2).
    [ "$(git -C "$CLONE" symbolic-ref --short HEAD)" = "feat/x" ]
    run git -C "$CLONE" ls-files --unmerged
    assert_output --partial "conflict.txt"
}

@test "teardown --force --discard-changes force-switches to main and deletes branch" {
    run_in_bash "cd '$CLONE' && gbr teardown --force --discard-changes 2>&1"
    assert_success
    assert_output --partial "Discarded local changes"
    assert_output --partial "Teardown complete"

    # Landed on main, feature branch gone, merge state cleared.
    [ "$(git -C "$CLONE" symbolic-ref --short HEAD)" = "main" ]
    run git -C "$CLONE" rev-parse --verify --quiet feat/x
    assert_failure
    run git -C "$CLONE" ls-files --unmerged
    assert_output ""
}

@test "teardown --help documents --discard-changes" {
    run_in_bash "gbr teardown --help 2>&1"
    assert_success
    assert_output --partial "--discard-changes"
    assert_output --partial "DESTRUCTIVE"
    # --force is now described as non-destructive.
    assert_output --partial "NON-destructive"
}
