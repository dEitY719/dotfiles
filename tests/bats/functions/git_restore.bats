#!/usr/bin/env bats
# tests/bats/functions/git_restore.bats
# Test the grs friendly `git restore` wrapper (issue #1146).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Emit a shell snippet that creates a fresh git repo in $tmp with one
# committed file f.txt (content "original") and cd's into it.
_grs_repo_setup() {
    printf '%s' '
        tmp=$(mktemp -d)
        cd "$tmp"
        git init -q -b main
        git config user.email t@t; git config user.name t
        printf "original\n" > f.txt
        git add f.txt
        git commit -q -m init
    '
}

# --- function existence / override ---

@test "bash: grs function exists" {
    run_in_bash 'declare -f grs >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: grs resolves to a function (overrides the alias)" {
    run_in_bash '[ "$(type -t grs)" = "function" ] && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _grs_help function exists" {
    run_in_bash 'declare -f _grs_help >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: grs --help prints usage without touching git" {
    run_in_bash 'grs --help'
    assert_success
    assert_output --partial "git restore"
}

# --- accident: untracked path ---

@test "bash: grs on untracked path diagnoses and does not restore" {
    run_in_bash "$(_grs_repo_setup)"'
        printf "junk\n" > untracked.txt
        grs untracked.txt; echo "RC=$?"
        rm -rf "$tmp"
    '
    assert_output --partial "untracked"
    assert_output --partial "git clean"
    assert_output --partial "RC=1"
}

# --- accident: untracked broken symlink (not a typo) ---

@test "bash: grs on an untracked broken symlink diagnoses untracked, not typo" {
    run_in_bash "$(_grs_repo_setup)"'
        ln -s /nonexistent/target dangling.link
        grs dangling.link; echo "RC=$?"
        rm -rf "$tmp"
    '
    assert_output --partial "untracked"
    refute_output --partial "오타"
    assert_output --partial "RC=1"
}

# --- accident: missing path (typo) ---

@test "bash: grs on missing path diagnoses a typo" {
    run_in_bash "$(_grs_repo_setup)"'
        grs does-not-exist.txt; echo "RC=$?"
        rm -rf "$tmp"
    '
    assert_output --partial "오타"
    assert_output --partial "RC=1"
}

# --- caution: staged-only ---

@test "bash: grs on staged-only path suggests --staged" {
    run_in_bash "$(_grs_repo_setup)"'
        printf "changed\n" > f.txt
        git add f.txt
        grs f.txt; echo "RC=$?"
        rm -rf "$tmp"
    '
    assert_output --partial "unstage"
    assert_output --partial "--staged"
    assert_output --partial "RC=1"
}

# --- info: no-op ---

@test "bash: grs on unchanged tracked path reports no-op with exit 0" {
    run_in_bash "$(_grs_repo_setup)"'
        grs f.txt; echo "RC=$?"
        rm -rf "$tmp"
    '
    assert_output --partial "no-op"
    assert_output --partial "RC=0"
}

# --- normal: real restore happens ---

@test "bash: grs on a worktree-modified path actually restores it" {
    run_in_bash "$(_grs_repo_setup)"'
        printf "changed\n" > f.txt
        grs f.txt >/dev/null 2>&1
        printf "AFTER: "; cat f.txt
        rm -rf "$tmp"
    '
    assert_success
    assert_output --partial "AFTER: original"
}

# --- passthrough: advanced flag skips preflight ---

@test "bash: grs --staged unstages (advanced flag passes through)" {
    run_in_bash "$(_grs_repo_setup)"'
        printf "changed\n" > f.txt
        git add f.txt
        grs --staged f.txt
        printf "STAGED: "; git diff --cached --name-only
        echo "(end)"
        rm -rf "$tmp"
    '
    assert_success
    # After unstage, nothing remains staged.
    assert_output --partial "STAGED: (end)"
}

# --- fallback: outside a git repo defers to raw git ---

@test "bash: grs outside a git repo falls back to raw git" {
    run_in_bash '
        tmp=$(mktemp -d)
        cd "$tmp"
        grs some-file.txt 2>&1; echo "RC=$?"
        rm -rf "$tmp"
    '
    # Raw git restore errors here (not a repo); we just must not crash our fn.
    assert_output --partial "RC="
    refute_output --partial "오타"
}
