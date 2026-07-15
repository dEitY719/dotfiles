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
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr=123"* ]]
    [[ "$output" == *"remote=origin"* ]]
    [[ "$output" == *"reply_mode=inline"* ]]
}

@test "pr + remote positional" {
    run devx_pr_review_all_parse 123 upstream
    [ "$status" -eq 0 ]
    [[ "$output" == *"remote=upstream"* ]]
}

@test "--defer-reply 8 -> reply_mode=defer reply_delay=8" {
    run devx_pr_review_all_parse 123 --defer-reply 8
    [ "$status" -eq 0 ]
    [[ "$output" == *"reply_mode=defer"* ]]
    [[ "$output" == *"reply_delay=8"* ]]
}

@test "--no-reply wins over --defer-reply" {
    run devx_pr_review_all_parse 123 --defer-reply 8 --no-reply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reply_mode=none"* ]]
}

@test "missing PR -> exit 2" {
    run devx_pr_review_all_parse
    [ "$status" -eq 2 ]
}

@test "non-integer PR -> exit 2" {
    run devx_pr_review_all_parse abc
    [ "$status" -eq 2 ]
}

@test "--defer-reply non-integer -> exit 2" {
    run devx_pr_review_all_parse 123 --defer-reply x
    [ "$status" -eq 2 ]
}

@test "unknown flag -> exit 2" {
    run devx_pr_review_all_parse 123 --bogus
    [ "$status" -eq 2 ]
}

@test "pr + literal origin remote + extra positional -> exit 2" {
    run devx_pr_review_all_parse 123 origin extra
    [ "$status" -eq 2 ]
}

@test "pr + literal origin remote (no extra) -> exit 0 with remote=origin" {
    run devx_pr_review_all_parse 123 origin
    [ "$status" -eq 0 ]
    [[ "$output" == *"remote=origin"* ]]
}

@test "help flag -> help_requested" {
    run devx_pr_review_all_parse --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"help_requested=1"* ]]
}
