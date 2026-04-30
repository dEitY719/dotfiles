#!/usr/bin/env bats
# tests/bats/functions/git_worktree_orphan.bats
# Issue #282: orphan-worktree recovery UX
#
# Covers:
#   - `gwt teardown` from inside an orphaned worktree (parent repo deleted)
#     surfaces a recovery hint instead of bare "Not inside a git repository".
#   - `gwt prune <path>` rejects with a friendly hint instead of git's raw
#     `usage: git worktree prune` error.
#   - `gwt ls` flags worktrees whose `.git` pointer leads outside the active
#     repo's admin dir or to a missing admin dir.

load '../test_helper'

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A standard origin <- clone <- worktree triple, used by prune-passthrough tests
# that just need a healthy git environment.
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

# Same as above, but then deletes the clone's .git so the worktree's `.git`
# pointer now leads to a missing admin dir — exactly the situation the user
# hit in #282 after their parent repo was removed.
_setup_orphan_worktree() {
    _setup_fake_repo
    rm -rf "$CLONE/.git"
}

# A repo with a worktree whose `.git` pointer has been forged to point at a
# non-existent path. From the active repo's POV, `git worktree list` shows it
# fine; the on-disk `.git` is the broken half. Used to exercise gwt ls's
# health probe.
_setup_foreign_pointer_worktree() {
    REPO="$TEST_TEMP_HOME/repo"
    WT_FOREIGN="$TEST_TEMP_HOME/repo-foreign-1"

    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

    git init -q --initial-branch=main "$REPO"
    (
        cd "$REPO"
        echo base > base.txt
        git add base.txt
        git commit -q -m "base"
    )
    git -C "$REPO" worktree add -q -b wt/foreign/1 "$WT_FOREIGN" main

    printf 'gitdir: %s/missing\n' "$TEST_TEMP_HOME" > "$WT_FOREIGN/.git"
}

setup() {
    setup_isolated_home
}

teardown() {
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Bug #1: orphan-worktree teardown
# ---------------------------------------------------------------------------

@test "teardown: orphan worktree (parent repo gone) shows recovery hint" {
    _setup_orphan_worktree

    run_in_bash "cd '$WORKTREE' && gwt teardown 2>&1"
    assert_failure
    # Specific diagnostic mentions the broken pointer
    assert_output --partial "parent repo is gone"
    assert_output --partial ".git points to"
    # Recovery instructions name the orphan path
    assert_output --partial "$WORKTREE"
    assert_output --partial "rm -rf"
    assert_output --partial "gwt prune"
    # The bare/legacy message should NOT be the only thing shown
    refute_output --partial "❌ Not inside a git repository"
}

@test "teardown --all: orphan cwd shows recovery hint, not bare error" {
    _setup_orphan_worktree

    run_in_bash "cd '$WORKTREE' && gwt teardown --all --force 2>&1"
    assert_failure
    assert_output --partial "parent repo is gone"
    refute_output --partial "❌ Not inside a git repository"
}

@test "teardown: truly non-git pwd still gets the bare error" {
    # A plain temp dir with no .git anything is not an orphan worktree.
    # Make sure the helper falls through to the standard message.
    NON_GIT="$TEST_TEMP_HOME/not-a-repo"
    mkdir -p "$NON_GIT"

    run_in_bash "cd '$NON_GIT' && gwt teardown 2>&1"
    assert_failure
    assert_output --partial "Not inside a git repository"
    refute_output --partial "parent repo is gone"
}

# ---------------------------------------------------------------------------
# Bug #2: gwt prune argument validation
# ---------------------------------------------------------------------------

@test "prune: rejects path argument with friendly hint" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune /some/path 2>&1"
    assert_failure
    assert_output --partial "does not accept a path argument"
    assert_output --partial "/some/path"
    assert_output --partial "gwt remove"
    # Must not fall through to git's raw usage line
    refute_output --partial "usage: git worktree prune"
}

@test "prune: --help shows usage with no-path warning" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune --help 2>&1"
    assert_success
    assert_output --partial "gwt prune"
    assert_output --partial "Does NOT take a path argument"
}

@test "prune: rejects unknown flag with hint to --help" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune --bogus 2>&1"
    assert_failure
    assert_output --partial "Unknown option"
    assert_output --partial "gwt prune --help"
}

@test "prune: bare invocation still works (no args)" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune 2>&1"
    assert_success
}

@test "prune: -v passthrough to git worktree prune" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune -v 2>&1"
    assert_success
}

@test "prune: --expire <when> two-arg form passes through" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt prune --expire 1.day.ago 2>&1"
    assert_success
}

# ---------------------------------------------------------------------------
# Bug #3: gwt ls health probe
# ---------------------------------------------------------------------------

@test "list: flags worktree with missing admin dir" {
    _setup_foreign_pointer_worktree

    run_in_bash "cd '$REPO' && gwt ls 2>&1"
    assert_success
    assert_output --partial "$WT_FOREIGN"
    assert_output --partial "orphan/broken worktree"
    assert_output --partial "admin dir missing"
}

@test "list: healthy worktree triggers no warning" {
    _setup_fake_repo

    run_in_bash "cd '$CLONE' && gwt ls 2>&1"
    assert_success
    refute_output --partial "orphan/broken worktree"
    refute_output --partial "admin dir missing"
}

@test "list: missing-on-disk worktree path is flagged" {
    _setup_fake_repo
    # Remove only the worktree's working tree, leave the admin entry behind.
    rm -rf "$WORKTREE"

    run_in_bash "cd '$CLONE' && gwt ls 2>&1"
    assert_success
    assert_output --partial "path missing on disk"
    assert_output --partial "$WORKTREE"
}
