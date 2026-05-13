#!/usr/bin/env bats
# tests/bats/functions/git_worktree_help.bats
# Tests for issue #605 — gwt help entry-point activation + remove/prune
# disambiguation.
#
# Behavior under test:
#   - `gwt`, `gwt -h`, `gwt --help`, `gwt help` all show the standalone help
#     instead of an error + hint (previous behavior returned 1).
#   - `gwt help <section>` forwards to `gwt_help <section>` and shows the
#     section detail (equivalent to `gwt-help <section>`).
#   - The summary distinguishes `remove` (deletes worktree dir + branch)
#     from `prune` (cleans stale .git/worktrees/ entries only).
#   - `gwt remove -h` and `gwt prune -h` cross-reference each other.
#   - `gwt remove --force` (path/name omitted) shows a clear
#     "Missing <path|name|all>" error instead of misinterpreting `--force`
#     as a worktree name.
#   - `gwt-help` alias still works (backward compat).
#   - Unknown command hint points to `gwt help` (not legacy `gwt-help`).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Help entry points: gwt / gwt -h / gwt --help / gwt help
# ---------------------------------------------------------------------------

@test "help: bare 'gwt' invocation shows help (no error)" {
    run_in_bash "gwt"
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "help: 'gwt -h' shows help" {
    run_in_bash "gwt -h"
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "help: 'gwt --help' shows help" {
    run_in_bash "gwt --help"
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "help: 'gwt help' shows help" {
    run_in_bash "gwt help"
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "help: 'gwt help <section>' shows section detail" {
    run_in_bash "gwt help spawn"
    assert_success
    assert_output --partial "spawn"
}

@test "help: 'gwt help --list' lists sections" {
    run_in_bash "gwt help --list"
    assert_success
    assert_output --partial "spawn"
    assert_output --partial "teardown"
}

# ---------------------------------------------------------------------------
# Summary disambiguates remove vs prune
# ---------------------------------------------------------------------------

@test "help: summary says remove deletes worktree dir + branch" {
    run_in_bash "gwt help"
    assert_success
    assert_output --partial "remove"
    assert_output --partial "delete worktree dir + branch"
}

@test "help: summary says prune cleans stale .git/worktrees/ refs" {
    run_in_bash "gwt help"
    assert_success
    assert_output --partial "prune"
    assert_output --partial "stale .git/worktrees/ refs"
}

# ---------------------------------------------------------------------------
# remove/prune -h cross-references
# ---------------------------------------------------------------------------

@test "help: 'gwt remove -h' cross-references gwt prune" {
    run_in_bash "gwt remove -h"
    assert_success
    assert_output --partial "gwt prune"
}

@test "help: 'gwt prune -h' cross-references gwt remove" {
    run_in_bash "gwt prune -h"
    assert_success
    assert_output --partial "gwt remove"
}

# ---------------------------------------------------------------------------
# 'gwt remove --force' (flag as first arg) — error message clarity
# ---------------------------------------------------------------------------

@test "remove: flag as first arg shows Missing <path|name|all> error" {
    run_in_bash "gwt remove --force 2>&1"
    assert_failure
    assert_output --partial "Missing <path|name|all>"
    refute_output --partial "No worktree found: --force"
}

@test "remove: flag as first arg suggests corrective forms" {
    run_in_bash "gwt remove --force 2>&1"
    assert_failure
    assert_output --partial "gwt remove all --force"
    assert_output --partial "gwt remove <path|name> --force"
}

# ---------------------------------------------------------------------------
# Backward compatibility: gwt-help alias still defined
#
# bash `--noprofile --norc -c` runs non-interactively and parses the entire
# `-c` string with alias expansion off, so we cannot invoke `gwt-help`
# directly in this harness — we verify the alias is defined and that the
# function it points at (`gwt_help`) is reachable. In actual user-
# interactive bash, `expand_aliases` is on and `gwt-help` works as before.
# ---------------------------------------------------------------------------

@test "compat: 'gwt-help' alias is defined" {
    run_in_bash "alias gwt-help"
    assert_success
    assert_output --partial "gwt_help"
}

@test "compat: gwt_help function is reachable in bash" {
    run_in_bash "gwt_help"
    assert_success
    assert_output --partial "sections"
}

@test "compat: gwt_help function accepts section arg in bash" {
    run_in_bash "gwt_help spawn"
    assert_success
    assert_output --partial "spawn"
}

# ---------------------------------------------------------------------------
# Unknown command hint
# ---------------------------------------------------------------------------

@test "dispatch: unknown command hint points to 'gwt help'" {
    run_in_bash "gwt bogus 2>&1"
    assert_failure
    assert_output --partial "Unknown command: bogus"
    assert_output --partial "Run: gwt help"
}

# ---------------------------------------------------------------------------
# Same behavior under zsh
# ---------------------------------------------------------------------------

@test "zsh: bare 'gwt' shows help" {
    run_in_zsh "gwt"
    assert_success
    assert_output --partial "Usage: gwt help"
}

@test "zsh: 'gwt help spawn' shows section detail" {
    run_in_zsh "gwt help spawn"
    assert_success
    assert_output --partial "spawn"
}

@test "zsh: 'gwt remove --force' shows missing-path error" {
    run_in_zsh "gwt remove --force 2>&1"
    assert_failure
    assert_output --partial "Missing <path|name|all>"
}

@test "zsh: 'gwt-help' alias still works" {
    run_in_zsh "gwt-help"
    assert_success
    assert_output --partial "sections"
}
