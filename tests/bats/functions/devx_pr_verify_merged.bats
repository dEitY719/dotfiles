#!/usr/bin/env bats
# tests/bats/functions/devx_pr_verify_merged.bats
# Unit tests for devx_pr_verify_merged_parse (pure arg parser).
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_verify_merged.sh"
}

@test "no args -> defaults, pr empty (auto-detect at runtime)" {
    run devx_pr_verify_merged_parse
    assert_success
    assert_line "pr="
    assert_line "remote=origin"
    assert_line "matrix=auto"
    assert_line "env_axes="
    assert_line "clone_dir="
    assert_line "diff_check=1"
    assert_line "issue_mode=create"
    assert_line "post_comment=1"
}

@test "pr only -> remote origin" {
    run devx_pr_verify_merged_parse 123
    assert_success
    assert_line "pr=123"
    assert_line "remote=origin"
}

@test "pr + remote positional" {
    run devx_pr_verify_merged_parse 123 upstream
    assert_success
    assert_line "pr=123"
    assert_line "remote=upstream"
}

# A first positional that does NOT start with a digit is the remote, not a
# malformed PR# — that is how `[pr-number] [remote]` with an optional
# pr-number stays expressible. Digit-leading typos are still PR# errors
# (see "digit-leading typo stays a PR# error" below).
@test "non-digit first positional -> remote, not a PR# error" {
    run devx_pr_verify_merged_parse abc
    assert_success
    assert_line "pr="
    assert_line "remote=abc"
}

@test "pr '0' -> exit 2 (zero is not a positive integer)" {
    run devx_pr_verify_merged_parse 0
    assert_failure 2
}

@test "pr '00' -> exit 2 (all-zero rejected)" {
    run devx_pr_verify_merged_parse 00
    assert_failure 2
}

@test "--matrix full ok" {
    run devx_pr_verify_merged_parse --matrix full
    assert_success
    assert_line "matrix=full"
}

@test "--matrix=full equals form ok" {
    run devx_pr_verify_merged_parse --matrix=full
    assert_success
    assert_line "matrix=full"
}

@test "--matrix bogus -> exit 2" {
    run devx_pr_verify_merged_parse --matrix bogus
    assert_failure 2
    assert_output --partial "--matrix must be auto or full: 'bogus'"
}

@test "--matrix with no value -> exit 2" {
    run devx_pr_verify_merged_parse --matrix
    assert_failure 2
}

@test "--matrix= empty equals form -> exit 2" {
    run devx_pr_verify_merged_parse --matrix=
    assert_failure 2
    assert_output --partial "--matrix value must not be empty"
}

@test "--matrix with empty string value -> exit 2" {
    run devx_pr_verify_merged_parse --matrix ""
    assert_failure 2
    assert_output --partial "--matrix value must not be empty"
}

@test "--env single axis ok" {
    run devx_pr_verify_merged_parse --env path
    assert_success
    assert_line "env_axes=path"
}

@test "--env CSV of axes ok" {
    run devx_pr_verify_merged_parse --env path,locale,shell,eol
    assert_success
    assert_line "env_axes=path,locale,shell,eol"
}

@test "--env= equals form ok" {
    run devx_pr_verify_merged_parse --env=locale
    assert_success
    assert_line "env_axes=locale"
}

@test "--env with unknown axis -> exit 2" {
    run devx_pr_verify_merged_parse --env path,bogus
    assert_failure 2
    assert_output --partial "--env axis must be one of path,locale,shell,eol: 'bogus'"
}

@test "--env with trailing comma -> exit 2" {
    run devx_pr_verify_merged_parse --env path,
    assert_failure 2
    assert_output --partial "--env axis must be one of path,locale,shell,eol: ''"
}

@test "--env with empty element -> exit 2" {
    run devx_pr_verify_merged_parse --env path,,eol
    assert_failure 2
    assert_output --partial "--env axis must be one of path,locale,shell,eol: ''"
}

@test "--env with no value -> exit 2" {
    run devx_pr_verify_merged_parse --env
    assert_failure 2
}

@test "--env= empty equals form -> exit 2" {
    run devx_pr_verify_merged_parse --env=
    assert_failure 2
    assert_output --partial "--env value must not be empty"
}

@test "--env with empty string value -> exit 2" {
    run devx_pr_verify_merged_parse --env ""
    assert_failure 2
    assert_output --partial "--env value must not be empty"
}

@test "--clone-dir space form" {
    run devx_pr_verify_merged_parse --clone-dir /tmp/verify-clone
    assert_success
    assert_line "clone_dir=/tmp/verify-clone"
}

@test "--clone-dir= equals form preserves spaces" {
    run devx_pr_verify_merged_parse --clone-dir="/tmp/my clone"
    assert_success
    assert_line "clone_dir=/tmp/my clone"
}

@test "--clone-dir with no value -> exit 2" {
    run devx_pr_verify_merged_parse --clone-dir
    assert_failure 2
}

@test "--clone-dir= empty equals form -> exit 2" {
    run devx_pr_verify_merged_parse --clone-dir=
    assert_failure 2
    assert_output --partial "--clone-dir value must not be empty"
}

@test "--clone-dir with empty string value -> exit 2" {
    run devx_pr_verify_merged_parse --clone-dir ""
    assert_failure 2
    assert_output --partial "--clone-dir value must not be empty"
}

@test "--no-diff-check -> diff_check=0" {
    run devx_pr_verify_merged_parse --no-diff-check
    assert_success
    assert_line "diff_check=0"
}

@test "--dry-run -> issue_mode=dry-run" {
    run devx_pr_verify_merged_parse --dry-run
    assert_success
    assert_line "issue_mode=dry-run"
}

@test "--no-issue -> issue_mode=none" {
    run devx_pr_verify_merged_parse --no-issue
    assert_success
    assert_line "issue_mode=none"
}

@test "--no-issue wins over --dry-run" {
    run devx_pr_verify_merged_parse --dry-run --no-issue
    assert_success
    assert_line "issue_mode=none"
}

@test "--no-comment -> post_comment=0" {
    run devx_pr_verify_merged_parse --no-comment
    assert_success
    assert_line "post_comment=0"
    assert_line "issue_mode=create"
}

@test "unknown flag -> exit 2" {
    run devx_pr_verify_merged_parse 123 --bogus
    assert_failure 2
    assert_output --partial "Unknown flag: --bogus"
}

@test "single-dash typo -> Unknown flag, not a PR# error" {
    run devx_pr_verify_merged_parse -x
    assert_failure 2
    assert_output --partial "Unknown flag: -x"
    refute_output --partial "PR# must be a positive integer"
}

@test "single-dash typo after a pr -> Unknown flag" {
    run devx_pr_verify_merged_parse 123 -x
    assert_failure 2
    assert_output --partial "Unknown flag: -x"
}

@test "pr + literal origin remote (no extra) -> exit 0 with remote=origin" {
    run devx_pr_verify_merged_parse 123 origin
    assert_success
    assert_line "remote=origin"
}

@test "third positional -> exit 2" {
    run devx_pr_verify_merged_parse 123 origin extra
    assert_failure 2
    assert_output --partial "Unexpected positional arg: extra"
}

@test "remote-only positional -> pr empty (auto-detect), remote used" {
    run devx_pr_verify_merged_parse upstream
    assert_success
    assert_line "pr="
    assert_line "remote=upstream"
}

@test "pr + remote still both resolve" {
    run devx_pr_verify_merged_parse 1273 upstream
    assert_success
    assert_line "pr=1273"
    assert_line "remote=upstream"
}

@test "digit-leading typo stays a PR# error, not a remote" {
    run devx_pr_verify_merged_parse 12a
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: '12a'"
}

# #1748: `#N` is the common GitHub PR notation and must classify as a PR#,
# not fall through to the remote-name branch.
@test "hash-prefixed PR# -> pr stripped of '#', remote defaults to origin" {
    run devx_pr_verify_merged_parse "#1745"
    assert_success
    assert_line "pr=1745"
    assert_line "remote=origin"
}

@test "hash-prefixed digit-leading typo stays a PR# error, not a remote" {
    run devx_pr_verify_merged_parse "#12a"
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: '12a'"
}

# codex review on PR #1749: a bare "#" strips to an empty pr, which must not
# silently bypass validation and fall back to PR auto-detection.
@test "bare hash with no digits -> exit 2, not silent auto-detect fallback" {
    run devx_pr_verify_merged_parse "#"
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: ''"
}

@test "remote-only + extra positional -> exit 2" {
    run devx_pr_verify_merged_parse upstream extra
    assert_failure 2
    assert_output --partial "Unexpected positional arg: extra"
}

@test "-h -> help_requested" {
    run devx_pr_verify_merged_parse -h
    assert_success
    assert_output --partial "help_requested=1"
}

@test "--help -> help_requested" {
    run devx_pr_verify_merged_parse --help
    assert_success
    assert_output --partial "help_requested=1"
}

@test "help word -> help_requested" {
    run devx_pr_verify_merged_parse help
    assert_success
    assert_output --partial "help_requested=1"
}

@test "combined flags resolve together" {
    run devx_pr_verify_merged_parse 99 upstream --matrix full \
        --env path,locale,shell,eol --clone-dir /tmp/verify-clone \
        --no-diff-check --dry-run --no-comment
    assert_success
    assert_line "pr=99"
    assert_line "remote=upstream"
    assert_line "matrix=full"
    assert_line "env_axes=path,locale,shell,eol"
    assert_line "clone_dir=/tmp/verify-clone"
    assert_line "diff_check=0"
    assert_line "issue_mode=dry-run"
    assert_line "post_comment=0"
}

# The parser lives in shell-common/functions/, which zsh/main.zsh auto-sources
# into the user's interactive shell — so every variable it assigns must be
# `local`. These leak guards call the function DIRECTLY (no `run`): `run`
# executes in a subshell, where a global assignment would be invisible and the
# regression would pass unnoticed.
@test "parse does not leak pr/remote into the caller's shell" {
    pr="SENTINEL_PR"
    remote="SENTINEL_REMOTE"
    devx_pr_verify_merged_parse 123 upstream >/dev/null
    [ "$pr" = "SENTINEL_PR" ]
    [ "$remote" = "SENTINEL_REMOTE" ]
}

@test "parse does not leak matrix/env_axes/clone_dir into the caller's shell" {
    matrix="SENTINEL_MATRIX"
    env_axes="SENTINEL_ENV_AXES"
    clone_dir="SENTINEL_CLONE_DIR"
    devx_pr_verify_merged_parse --matrix full --env path,locale \
        --clone-dir /tmp/verify-clone >/dev/null
    [ "$matrix" = "SENTINEL_MATRIX" ]
    [ "$env_axes" = "SENTINEL_ENV_AXES" ]
    [ "$clone_dir" = "SENTINEL_CLONE_DIR" ]
}

@test "parse does not leak diff_check/issue_mode/post_comment/_rest/_item" {
    diff_check="SENTINEL_DIFF_CHECK"
    issue_mode="SENTINEL_ISSUE_MODE"
    post_comment="SENTINEL_POST_COMMENT"
    _rest="SENTINEL_REST"
    _item="SENTINEL_ITEM"
    devx_pr_verify_merged_parse --env path,eol --no-diff-check \
        --dry-run --no-comment >/dev/null
    [ "$diff_check" = "SENTINEL_DIFF_CHECK" ]
    [ "$issue_mode" = "SENTINEL_ISSUE_MODE" ]
    [ "$post_comment" = "SENTINEL_POST_COMMENT" ]
    [ "$_rest" = "SENTINEL_REST" ]
    [ "$_item" = "SENTINEL_ITEM" ]
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

@test "zsh: #1505 foreign-checkout guard warns when devx_pr_verify_merged.sh is sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_zsh '. "$SHELL_COMMON/functions/devx_pr_verify_merged.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_verify_merged.sh"
}

@test "bash: #1505 foreign-checkout guard warns when devx_pr_verify_merged.sh is sourced under bash" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_bash '. "$SHELL_COMMON/functions/devx_pr_verify_merged.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_verify_merged.sh"
}
