#!/usr/bin/env bats
# tests/bats/functions/git.bats
# Test git utility functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- function existence ---

@test "bash: git_log function exists" {
    run_in_bash 'declare -f git_log >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_log_upstream function exists" {
    run_in_bash 'declare -f git_log_upstream >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_branch function exists" {
    run_in_bash 'declare -f git_branch >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gb_clean_local function exists" {
    run_in_bash 'declare -f _gb_clean_local >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gb_clean_remote function exists" {
    run_in_bash 'declare -f _gb_clean_remote >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gb alias maps to git_branch" {
    run_in_bash 'alias gb | grep -q git_branch && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gl alias exists" {
    run_in_bash 'alias gl'
    assert_success
    assert_output --partial "git-log"
}

# --- gb -D remote behavior (server-side deletion against a local bare remote) ---

@test "bash: gb -D remote deletes non-main branches on the remote server" {
    run_in_bash '
        tmp=$(mktemp -d)
        git init -q -b main --bare "$tmp/remote.git"
        git clone -q "$tmp/remote.git" "$tmp/work" 2>/dev/null
        cd "$tmp/work"
        git config user.email t@t; git config user.name t
        git commit -q --allow-empty -m init
        git push -q origin HEAD:main
        git push -q origin HEAD:docs/some-spec
        git push -q origin HEAD:wt/issue-318/1
        _gb_clean_remote -y origin >/dev/null 2>&1
        printf "REMAINING: "
        git ls-remote --heads "$tmp/remote.git" | sed "s#.*refs/heads/##" | sort | tr "\n" " "
        echo
        rm -rf "$tmp"
    '
    assert_success
    assert_output --partial "REMAINING: main"
    refute_output --partial "docs/some-spec"
    refute_output --partial "wt/issue-318/1"
}

@test "bash: gb -D remote keeps main and reports nothing to delete when only main exists" {
    run_in_bash '
        tmp=$(mktemp -d)
        git init -q -b main --bare "$tmp/remote.git"
        git clone -q "$tmp/remote.git" "$tmp/work" 2>/dev/null
        cd "$tmp/work"
        git config user.email t@t; git config user.name t
        git commit -q --allow-empty -m init
        git push -q origin HEAD:main
        _gb_clean_remote -y origin
        rm -rf "$tmp"
    '
    assert_success
    assert_output --partial "No branches to delete"
}

@test "bash: gb -D <remote-name> hints 'gb -D remote' instead of failing silently" {
    run_in_bash '
        tmp=$(mktemp -d)
        git init -q -b main --bare "$tmp/remote.git"
        git clone -q "$tmp/remote.git" "$tmp/work" 2>/dev/null
        cd "$tmp/work"
        git config user.email t@t; git config user.name t
        git commit -q --allow-empty -m init
        git_branch -D origin
        status=$?
        rm -rf "$tmp"
        exit "$status"
    '
    assert_failure
    assert_output --partial "is a remote, not a branch"
    assert_output --partial "gb -D remote origin"
}

@test "bash: gb -D <local-branch-name-matching-remote> still deletes the local branch" {
    run_in_bash '
        tmp=$(mktemp -d)
        git init -q -b main --bare "$tmp/remote.git"
        git clone -q "$tmp/remote.git" "$tmp/work" 2>/dev/null
        cd "$tmp/work"
        git config user.email t@t; git config user.name t
        git commit -q --allow-empty -m init
        git branch origin
        git_branch -D origin
        rm -rf "$tmp"
    '
    assert_success
    assert_output --partial "Deleted branch origin"
}

# --- git worktree functions ---

@test "bash: gwt function exists" {
    run_in_bash 'declare -f gwt >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_list function exists" {
    run_in_bash 'declare -f git_worktree_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_add function exists" {
    run_in_bash 'declare -f git_worktree_add >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git_worktree_remove function exists" {
    run_in_bash 'declare -f git_worktree_remove >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# --- git_ssh_check ---

@test "bash: git_ssh_check function exists" {
    run_in_bash 'declare -f git_ssh_check >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: git-ssh-check alias exists" {
    run_in_bash 'alias git-ssh-check'
    assert_success
}

# --- git_log output (in a git repo) ---

@test "bash: git_log produces output in git repo" {
    run_in_bash "cd '${DOTFILES_ROOT}' && git_log"
    assert_success
}

# --- zsh parity ---

@test "zsh: git_log function exists" {
    run_in_zsh 'declare -f git_log >/dev/null && echo ok'
    assert_success
}

@test "zsh: gwt function exists" {
    run_in_zsh 'declare -f gwt >/dev/null && echo ok'
    assert_success
}

@test "zsh: git_ssh_check function exists" {
    run_in_zsh 'declare -f git_ssh_check >/dev/null && echo ok'
    assert_success
}
