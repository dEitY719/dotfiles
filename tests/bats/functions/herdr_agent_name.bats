#!/usr/bin/env bats
# tests/bats/functions/herdr_agent_name.bats
# Coverage for shell-common/functions/herdr_agent_name.sh (issue #1530).
#
# herdr validates every agent name against `^[a-z][a-z0-9_-]{0,31}$` and
# refuses the start outright when it does not match. Three call sites used to
# build that name with `tr -c 'A-Za-z0-9._-' '-'`, which *preserves* uppercase
# and dots because both are inside the kept set — so on `dEitY719/dotfiles` @
# `github.com` every name they produced was invalid and the whole unattended
# pipeline never launched a single session (76 recorded failures, 0 successes).
#
# T1-T9 pin the normalizer (`herdr_agent_repo_slug`): case folding, the owner
# and host being dropped, unsafe characters folding to `-`, run collapsing,
# the 16-character budget, and the rejection of input that normalizes to
# nothing.
#
# T10-T15 pin the composer (`herdr_agent_name`) — the three real shapes
# (`mt-<repo>`, `iw-<repo>-issue-<N>`, `mv-<repo>-pr-<N>`), herdr's rule
# itself as an assertion, and determinism (the property NF-1's singleton lock
# in pr_merge_train_cron.sh depends on).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# The rule herdr enforces, in one place. Every name assertion below runs
# through this so a future budget change cannot quietly break the contract.
assert_valid_herdr_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] ||
        fail "not a valid herdr agent name: '$1'"
}

# ---------------------------------------------------------------------------
# T1-T9: herdr_agent_repo_slug — normalization
# ---------------------------------------------------------------------------

@test "T1: uppercase folds to lowercase and the owner is dropped" {
    run_in_bash 'herdr_agent_repo_slug dEitY719/dotfiles'
    assert_success
    assert_output "dotfiles"
}

@test "T2: a host-qualified identifier also reduces to the repo alone" {
    run_in_bash 'herdr_agent_repo_slug github.com/dEitY719/dotfiles'
    assert_success
    assert_output "dotfiles"
}

@test "T3: a bare repo name passes through" {
    run_in_bash 'herdr_agent_repo_slug dotfiles'
    assert_success
    assert_output "dotfiles"
}

@test "T4: dots and other unsafe characters fold to a dash" {
    run_in_bash 'herdr_agent_repo_slug "acme/My.Repo Name"'
    assert_success
    assert_output "my-repo-name"
}

@test "T5: runs of dashes collapse and leading/trailing dashes are stripped" {
    run_in_bash 'herdr_agent_repo_slug "--a...b--"'
    assert_success
    assert_output "a-b"
}

@test "T6: the slug is truncated to 16 characters by default" {
    run_in_bash 'herdr_agent_repo_slug acme/abcdefghijklmnopqrstuvwxyz'
    assert_success
    assert_output "abcdefghijklmnop"
}

@test "T7: truncation never leaves a trailing dash" {
    # 16 chars would cut right after the dash: `abcdefghijklmno-`.
    run_in_bash 'herdr_agent_repo_slug acme/abcdefghijklmno-pqrs'
    assert_success
    assert_output "abcdefghijklmno"
}

@test "T8: an explicit budget overrides the 16-character default" {
    run_in_bash 'herdr_agent_repo_slug acme/dotfiles 4'
    assert_success
    assert_output "dotf"
}

@test "T9: input that normalizes to nothing is refused, not silently empty" {
    run_in_bash 'herdr_agent_repo_slug "acme/..."'
    assert_failure
    assert_output ""
}

# ---------------------------------------------------------------------------
# T10-T15: herdr_agent_name — composition
# ---------------------------------------------------------------------------

@test "T10: merge-train's name is the repo alone, with no number" {
    run_in_bash 'herdr_agent_name mt dEitY719/dotfiles'
    assert_success
    assert_output "mt-dotfiles"
    assert_valid_herdr_name "$output"
}

@test "T11: issue-watcher's name carries the issue number" {
    run_in_bash 'herdr_agent_name iw dEitY719/dotfiles issue-1495'
    assert_success
    assert_output "iw-dotfiles-issue-1495"
    assert_valid_herdr_name "$output"
}

@test "T12: post-merge-verify's name carries the PR number" {
    run_in_bash 'herdr_agent_name mv dEitY719/dotfiles pr-1528'
    assert_success
    assert_output "mv-dotfiles-pr-1528"
    assert_valid_herdr_name "$output"
}

@test "T13: the worst case — 16-char repo plus a 5-digit number — still fits" {
    run_in_bash 'herdr_agent_name iw acme/abcdefghijklmnopqrstuvwxyz issue-99999'
    assert_success
    assert_output "iw-abcdefghijklmnop-issue-99999"
    assert_valid_herdr_name "$output"
}

@test "T14: a name built from an unusable repo identifier is refused" {
    run_in_bash 'herdr_agent_name mt "acme/..."'
    assert_failure
    assert_output ""
}

@test "T15: the same repo yields the same name twice (NF-1 singleton lock)" {
    run_in_bash 'herdr_agent_name mt dEitY719/dotfiles; printf ":"; herdr_agent_name mt dEitY719/dotfiles'
    assert_success
    assert_output "mt-dotfiles:mt-dotfiles"
}
