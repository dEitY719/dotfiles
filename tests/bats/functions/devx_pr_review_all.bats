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

@test "parse does not leak pr/remote/reply_mode/reply_delay/_no_reply/_remote_set into the caller's shell" {
    pr="SENTINEL_PR"
    remote="SENTINEL_REMOTE"
    reply_mode="SENTINEL_REPLY_MODE"
    reply_delay="SENTINEL_REPLY_DELAY"
    _no_reply="SENTINEL_NO_REPLY"
    _remote_set="SENTINEL_REMOTE_SET"
    devx_pr_review_all_parse 123 upstream --defer-reply 8 >/dev/null
    _rc=$?
    [ "$_rc" -eq 0 ]
    [ "$pr" = "SENTINEL_PR" ]
    [ "$remote" = "SENTINEL_REMOTE" ]
    [ "$reply_mode" = "SENTINEL_REPLY_MODE" ]
    [ "$reply_delay" = "SENTINEL_REPLY_DELAY" ]
    [ "$_no_reply" = "SENTINEL_NO_REPLY" ]
    [ "$_remote_set" = "SENTINEL_REMOTE_SET" ]
}

# ---------------------------------------------------------------------------
# #1454 foreign-checkout guard, propagated to this file by issue #1505.
#
# Mirrors tests/bats/functions/gh_pr_review.bats — zsh is the case that
# matters: the guard reads ${BASH_SOURCE[0]}, which bash always populated but
# zsh never does, so before #1454 the zsh path self-disabled on its first
# line. The file is re-sourced explicitly rather than read off the loader's
# own pass because both loaders source with `2>/dev/null` (safe_source /
# load_category), which would swallow the very stderr under test.
# ---------------------------------------------------------------------------

_setup_foreign_home_1505() {
    FOREIGN_HOME_1505="$BATS_TEST_TMPDIR/foreign-home-1505"
    mkdir -p "$FOREIGN_HOME_1505/dotfiles"
    git -C "$FOREIGN_HOME_1505/dotfiles" init -q -b main
    git -C "$FOREIGN_HOME_1505/dotfiles" -c user.email=t@t -c user.name=t \
        commit --allow-empty -q -m init
    export HOME="$FOREIGN_HOME_1505"
}

@test "zsh: #1505 foreign-checkout guard warns when devx_pr_review_all.sh is sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_zsh '. "$SHELL_COMMON/functions/devx_pr_review_all.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_review_all.sh"
}

@test "bash: #1505 foreign-checkout guard warns when devx_pr_review_all.sh is sourced under bash" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_bash '. "$SHELL_COMMON/functions/devx_pr_review_all.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_review_all.sh"
}
