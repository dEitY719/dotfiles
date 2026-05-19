#!/usr/bin/env bats
# tests/bats/skills/gh_pr_review_remote_url.bats
# Unit tests for `_gh_pr_review_parse_remote_url` — the Bug C fix from
# issue #694. Before #694, `gh_pr_review` called `gh repo view` without
# `-R <url>` and swallowed gh's stderr with `2>/dev/null`, masking the
# real cause of "could not resolve target repo from remote 'origin'".
# The parser is now pure-shell and bats-testable.
#
# Reuses the existing fixture which sources
# `shell-common/functions/gh_pr_review.sh` (same SSOT as the arg-parse
# tests in gh_pr_review_arg_parse.bats).

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh"
}

teardown() {
    teardown_isolated_home
}

# ---- happy paths ----------------------------------------------------------

@test "remote-url: https github URL with .git suffix → owner/repo" {
    run _gh_pr_review_parse_remote_url "https://github.com/dEitY719/dotfiles.git"
    assert_success
    [ "$output" = "dEitY719/dotfiles" ]
}

@test "remote-url: https github URL without .git suffix → owner/repo" {
    run _gh_pr_review_parse_remote_url "https://github.com/dEitY719/dotfiles"
    assert_success
    [ "$output" = "dEitY719/dotfiles" ]
}

@test "remote-url: ssh github URL (git@) → owner/repo" {
    run _gh_pr_review_parse_remote_url "git@github.com:dEitY719/dotfiles.git"
    assert_success
    [ "$output" = "dEitY719/dotfiles" ]
}

@test "remote-url: ssh:// github URL → owner/repo" {
    run _gh_pr_review_parse_remote_url "ssh://git@github.com/dEitY719/dotfiles.git"
    assert_success
    [ "$output" = "dEitY719/dotfiles" ]
}

@test "remote-url: trailing slash is stripped" {
    run _gh_pr_review_parse_remote_url "https://github.com/dEitY719/dotfiles/"
    assert_success
    [ "$output" = "dEitY719/dotfiles" ]
}

# ---- rejection paths ------------------------------------------------------

@test "remote-url: empty URL → fail with empty-URL message" {
    run _gh_pr_review_parse_remote_url ""
    assert_failure
    assert_output --partial "empty remote URL"
}

@test "remote-url: non-github host → fail with not-github message" {
    run _gh_pr_review_parse_remote_url "https://gitlab.com/owner/repo.git"
    assert_failure
    assert_output --partial "not a github.com remote"
}

@test "remote-url: malformed (no owner/repo path) → fail" {
    run _gh_pr_review_parse_remote_url "https://github.com/"
    assert_failure
    assert_output --partial "Could not parse owner/repo"
}

@test "remote-url: malformed (only owner) → fail" {
    run _gh_pr_review_parse_remote_url "https://github.com/dEitY719"
    assert_failure
    assert_output --partial "Could not parse owner/repo"
}
