#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all.bats
# Unit tests for devx_pr_review_all_parse (pure arg parser).
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_review_all.sh"
}

@test "pr only -> inline default, remote origin" {
    run devx_pr_review_all_parse 123
    assert_success
    assert_output --partial "pr=123"
    assert_output --partial "remote=origin"
    assert_output --partial "reply_mode=inline"
}

@test "pr + remote positional" {
    run devx_pr_review_all_parse 123 upstream
    assert_success
    assert_output --partial "remote=upstream"
}

@test "--defer-reply 8 -> reply_mode=defer reply_delay=8" {
    run devx_pr_review_all_parse 123 --defer-reply 8
    assert_success
    assert_output --partial "reply_mode=defer"
    assert_output --partial "reply_delay=8"
}

@test "--no-reply wins over --defer-reply" {
    run devx_pr_review_all_parse 123 --defer-reply 8 --no-reply
    assert_success
    assert_output --partial "reply_mode=none"
}

@test "missing PR -> exit 2" {
    run devx_pr_review_all_parse
    assert_failure 2
}

@test "non-integer PR -> exit 2" {
    run devx_pr_review_all_parse abc
    assert_failure 2
}

@test "--defer-reply non-integer -> exit 2" {
    run devx_pr_review_all_parse 123 --defer-reply x
    assert_failure 2
}

@test "unknown flag -> exit 2" {
    run devx_pr_review_all_parse 123 --bogus
    assert_failure 2
}

@test "pr + literal origin remote + extra positional -> exit 2" {
    run devx_pr_review_all_parse 123 origin extra
    assert_failure 2
}

@test "pr + literal origin remote (no extra) -> exit 0 with remote=origin" {
    run devx_pr_review_all_parse 123 origin
    assert_success
    assert_output --partial "remote=origin"
}

@test "PR '0' -> exit 2 (zero is not a positive integer)" {
    run devx_pr_review_all_parse 0
    assert_failure 2
}

@test "PR '00' -> exit 2 (all-zero rejected)" {
    run devx_pr_review_all_parse 00
    assert_failure 2
}

@test "--defer-reply 0 -> exit 2 (zero delay rejected)" {
    run devx_pr_review_all_parse 123 --defer-reply 0
    assert_failure 2
}

@test "help flag -> help_requested" {
    run devx_pr_review_all_parse --help
    assert_success
    assert_output --partial "help_requested=1"
}
