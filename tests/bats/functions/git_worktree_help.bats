#!/usr/bin/env bats
# tests/bats/functions/git_worktree_help.bats
# Tests for issue #605 (gwt help entry-point activation + remove/prune
# disambiguation) and issue #746 (canonical `gwt-help` enforcement —
# `gwt help` 공백 형식은 거부, dash 형식만 허용).
#
# Behavior under test:
#   - `gwt`, `gwt -h`, `gwt --help` show the standalone help summary
#     (canonical `Usage: gwt-help [section|--list|--all]` 템플릿).
#   - `gwt help` (legacy 공백 형식) 은 exit 1 + canonical entrypoint
#     안내 (#746) — `test_help_compact_policy.py` 의 SSOT 와 일치.
#   - `gwt_help <section>` (함수 직접 호출) 와 `gwt-help` alias 는 그대로 작동.
#   - The summary distinguishes `remove` (deletes worktree dir + branch)
#     from `prune` (cleans stale .git/worktrees/ entries only).
#   - `gwt remove -h` and `gwt prune -h` cross-reference each other.
#   - `gwt remove --force` (path/name omitted) shows a clear
#     "Missing <path|name|all>" error instead of misinterpreting `--force`
#     as a worktree name.
#   - Unknown command hint points to `gwt-help` (#746 canonical entrypoint).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Help entry points: gwt / gwt -h / gwt --help show summary (canonical form)
# ---------------------------------------------------------------------------

@test "help: bare 'gwt' invocation shows help (no error)" {
    run_in_bash "gwt"
    assert_success
    assert_output --partial "Usage: gwt-help"
}

@test "help: 'gwt -h' shows help" {
    run_in_bash "gwt -h"
    assert_success
    assert_output --partial "Usage: gwt-help"
}

@test "help: 'gwt --help' shows help" {
    run_in_bash "gwt --help"
    assert_success
    assert_output --partial "Usage: gwt-help"
}

# ---------------------------------------------------------------------------
# Legacy 'gwt help' (공백 형식) — rejected per #746 SSOT
# Section detail / --list 은 canonical `gwt_help` 함수로 검증
# ---------------------------------------------------------------------------

@test "help: 'gwt help' is rejected with canonical-entrypoint guidance (#746)" {
    run_in_bash "gwt help 2>&1"
    assert_failure
    assert_output --partial "canonical entrypoint: gwt-help"
}

@test "help: 'gwt_help <section>' (canonical) shows section detail" {
    run_in_bash "gwt_help spawn"
    assert_success
    assert_output --partial "spawn"
}

@test "help: 'gwt_help --list' (canonical) lists sections" {
    run_in_bash "gwt_help --list"
    assert_success
    assert_output --partial "spawn"
    assert_output --partial "teardown"
}

# ---------------------------------------------------------------------------
# Summary disambiguates remove vs prune (via canonical entry point)
# ---------------------------------------------------------------------------

@test "help: summary says remove deletes worktree dir + branch" {
    run_in_bash "gwt"
    assert_success
    assert_output --partial "remove"
    assert_output --partial "delete worktree dir + branch"
}

@test "help: summary says prune cleans stale .git/worktrees/ refs" {
    run_in_bash "gwt"
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

@test "remove: wildcard '*' in target is refused (defense-in-depth, gemini #606)" {
    # Even though the for-loop uses quoted globbing that renders '*' inert
    # in practice, accepting wildcards is confusing UX. Reject explicitly
    # and direct the user at the canonical batch entry point.
    run_in_bash "gwt remove '*' 2>&1"
    assert_failure
    assert_output --partial "Wildcards"
    assert_output --partial "gwt remove all"
}

@test "remove: wildcard '?' in target is refused" {
    run_in_bash "gwt remove 'a?b' 2>&1"
    assert_failure
    assert_output --partial "Wildcards"
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

@test "dispatch: unknown command hint points to 'gwt-help' (#746)" {
    run_in_bash "gwt bogus 2>&1"
    assert_failure
    assert_output --partial "Unknown command: bogus"
    assert_output --partial "Run: gwt-help"
}

# ---------------------------------------------------------------------------
# Same behavior under zsh
# ---------------------------------------------------------------------------

@test "zsh: bare 'gwt' shows help" {
    run_in_zsh "gwt"
    assert_success
    assert_output --partial "Usage: gwt-help"
}

@test "zsh: 'gwt_help spawn' (canonical) shows section detail" {
    run_in_zsh "gwt_help spawn"
    assert_success
    assert_output --partial "spawn"
}

@test "zsh: 'gwt help' (legacy) is rejected (#746)" {
    run_in_zsh "gwt help 2>&1"
    assert_failure
    assert_output --partial "canonical entrypoint: gwt-help"
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
