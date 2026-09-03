#!/usr/bin/env bats
# tests/bats/functions/devx_pr_verify_live.bats
# Unit tests for devx_pr_verify_live_parse (pure arg parser).
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_verify_live.sh"
}

@test "no args -> defaults, pr empty (auto-detect at runtime)" {
    run devx_pr_verify_live_parse
    assert_success
    assert_line "pr="
    assert_line "remote=origin"
    assert_line "url="
    assert_line "api_url="
    assert_line "start_cmd="
    assert_line "matrix=auto"
    assert_line "viewports="
    assert_line "locales="
    assert_line "issue_mode=create"
    assert_line "allow_remote_host=0"
    assert_line "post_comment=1"
}

@test "pr only -> remote origin" {
    run devx_pr_verify_live_parse 123
    assert_success
    assert_line "pr=123"
    assert_line "remote=origin"
}

@test "pr + remote positional" {
    run devx_pr_verify_live_parse 123 upstream
    assert_success
    assert_line "pr=123"
    assert_line "remote=upstream"
}

# A first positional that does NOT start with a digit is the remote, not a
# malformed PR# — that is how `[pr-number] [remote]` with an optional
# pr-number stays expressible. Digit-leading typos are still PR# errors
# (see "digit-leading typo stays a PR# error" below).
@test "non-digit first positional -> remote, not a PR# error" {
    run devx_pr_verify_live_parse abc
    assert_success
    assert_line "pr="
    assert_line "remote=abc"
}

@test "pr '0' -> exit 2 (zero is not a positive integer)" {
    run devx_pr_verify_live_parse 0
    assert_failure 2
}

@test "pr '00' -> exit 2 (all-zero rejected)" {
    run devx_pr_verify_live_parse 00
    assert_failure 2
}

@test "--url space form" {
    run devx_pr_verify_live_parse --url http://localhost:5173
    assert_success
    assert_line "url=http://localhost:5173"
}

@test "--url= equals form" {
    run devx_pr_verify_live_parse --url=https://staging.example.com
    assert_success
    assert_line "url=https://staging.example.com"
}

@test "non-http --url -> exit 2" {
    run devx_pr_verify_live_parse --url ftp://localhost
    assert_failure 2
}

@test "--url with no value -> exit 2" {
    run devx_pr_verify_live_parse --url
    assert_failure 2
}

@test "--url= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --url=
    assert_failure 2
    assert_output --partial "--url value must not be empty"
}

@test "--url with empty string value -> exit 2" {
    run devx_pr_verify_live_parse --url ""
    assert_failure 2
    assert_output --partial "--url value must not be empty"
}

@test "--api-url space form" {
    run devx_pr_verify_live_parse --api-url http://localhost:8000
    assert_success
    assert_line "api_url=http://localhost:8000"
}

@test "--api-url= equals form" {
    run devx_pr_verify_live_parse --api-url=https://api.example.com
    assert_success
    assert_line "api_url=https://api.example.com"
}

@test "non-http --api-url -> exit 2" {
    run devx_pr_verify_live_parse --api-url localhost:8000
    assert_failure 2
}

@test "--api-url= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --api-url=
    assert_failure 2
    assert_output --partial "--api-url value must not be empty"
}

@test "--api-url with empty string value -> exit 2" {
    run devx_pr_verify_live_parse --api-url ""
    assert_failure 2
    assert_output --partial "--api-url value must not be empty"
}

@test "--start space form preserves spaces" {
    run devx_pr_verify_live_parse --start "bun run dev:frontend"
    assert_success
    assert_line "start_cmd=bun run dev:frontend"
}

@test "--start= equals form preserves spaces" {
    run devx_pr_verify_live_parse --start="bun run dev:frontend"
    assert_success
    assert_line "start_cmd=bun run dev:frontend"
}

@test "--start with empty value -> exit 2" {
    run devx_pr_verify_live_parse --start ""
    assert_failure 2
    assert_output --partial "--start value must not be empty"
}

@test "--start= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --start=
    assert_failure 2
    assert_output --partial "--start value must not be empty"
}

@test "--matrix full ok" {
    run devx_pr_verify_live_parse --matrix full
    assert_success
    assert_line "matrix=full"
}

@test "--matrix=full equals form ok" {
    run devx_pr_verify_live_parse --matrix=full
    assert_success
    assert_line "matrix=full"
}

@test "--matrix bogus -> exit 2" {
    run devx_pr_verify_live_parse --matrix bogus
    assert_failure 2
}

@test "--matrix= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --matrix=
    assert_failure 2
    assert_output --partial "--matrix value must not be empty"
}

@test "--matrix with empty string value -> exit 2" {
    run devx_pr_verify_live_parse --matrix ""
    assert_failure 2
    assert_output --partial "--matrix value must not be empty"
}

@test "--viewports CSV of integers ok" {
    run devx_pr_verify_live_parse --viewports 1440,390
    assert_success
    assert_line "viewports=1440,390"
}

@test "--viewports= equals form ok" {
    run devx_pr_verify_live_parse --viewports=1440
    assert_success
    assert_line "viewports=1440"
}

@test "--viewports with non-numeric element -> exit 2" {
    run devx_pr_verify_live_parse --viewports 1440,abc
    assert_failure 2
}

@test "--viewports with trailing comma -> exit 2" {
    run devx_pr_verify_live_parse --viewports 1440,
    assert_failure 2
}

@test "--viewports= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --viewports=
    assert_failure 2
    assert_output --partial "--viewports value must not be empty"
}

@test "--viewports with empty string value -> exit 2" {
    run devx_pr_verify_live_parse --viewports ""
    assert_failure 2
    assert_output --partial "--viewports value must not be empty"
}

@test "--locales CSV ok" {
    run devx_pr_verify_live_parse --locales ko,en
    assert_success
    assert_line "locales=ko,en"
}

@test "--locales= equals form ok" {
    run devx_pr_verify_live_parse --locales=ko-KR
    assert_success
    assert_line "locales=ko-KR"
}

@test "--locales with empty element -> exit 2" {
    run devx_pr_verify_live_parse --locales ko,,en
    assert_failure 2
}

@test "--locales= empty equals form -> exit 2" {
    run devx_pr_verify_live_parse --locales=
    assert_failure 2
    assert_output --partial "--locales value must not be empty"
}

@test "--locales with empty string value -> exit 2" {
    run devx_pr_verify_live_parse --locales ""
    assert_failure 2
    assert_output --partial "--locales value must not be empty"
}

@test "--dry-run -> issue_mode=dry-run" {
    run devx_pr_verify_live_parse --dry-run
    assert_success
    assert_line "issue_mode=dry-run"
}

@test "--no-issue -> issue_mode=none" {
    run devx_pr_verify_live_parse --no-issue
    assert_success
    assert_line "issue_mode=none"
}

@test "--no-issue wins over --dry-run" {
    run devx_pr_verify_live_parse --dry-run --no-issue
    assert_success
    assert_line "issue_mode=none"
}

@test "--no-comment -> post_comment=0" {
    run devx_pr_verify_live_parse --no-comment
    assert_success
    assert_line "post_comment=0"
    assert_line "issue_mode=create"
}

@test "--allow-remote-host -> 1" {
    run devx_pr_verify_live_parse --allow-remote-host
    assert_success
    assert_line "allow_remote_host=1"
}

@test "unknown flag -> exit 2" {
    run devx_pr_verify_live_parse 123 --bogus
    assert_failure 2
    assert_output --partial "Unknown flag: --bogus"
}

@test "single-dash typo -> Unknown flag, not a PR# error" {
    run devx_pr_verify_live_parse -x
    assert_failure 2
    assert_output --partial "Unknown flag: -x"
    refute_output --partial "PR# must be a positive integer"
}

@test "single-dash typo after a pr -> Unknown flag" {
    run devx_pr_verify_live_parse 123 -x
    assert_failure 2
    assert_output --partial "Unknown flag: -x"
}

@test "pr + literal origin remote (no extra) -> exit 0 with remote=origin" {
    run devx_pr_verify_live_parse 123 origin
    assert_success
    assert_line "remote=origin"
}

@test "third positional -> exit 2" {
    run devx_pr_verify_live_parse 123 origin extra
    assert_failure 2
}

@test "remote-only positional -> pr empty (auto-detect), remote used" {
    run devx_pr_verify_live_parse upstream
    assert_success
    assert_line "pr="
    assert_line "remote=upstream"
}

@test "pr + remote still both resolve" {
    run devx_pr_verify_live_parse 1273 upstream
    assert_success
    assert_line "pr=1273"
    assert_line "remote=upstream"
}

@test "digit-leading typo stays a PR# error, not a remote" {
    run devx_pr_verify_live_parse 12a
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: '12a'"
}

# #1748: `#N` is the common GitHub PR notation and must classify as a PR#,
# not fall through to the remote-name branch.
@test "hash-prefixed PR# -> pr stripped of '#', remote defaults to origin" {
    run devx_pr_verify_live_parse "#1745"
    assert_success
    assert_line "pr=1745"
    assert_line "remote=origin"
}

@test "hash-prefixed digit-leading typo stays a PR# error, not a remote" {
    run devx_pr_verify_live_parse "#12a"
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: '12a'"
}

# codex review on PR #1749: a bare "#" strips to an empty pr, which must not
# silently bypass validation and fall back to PR auto-detection.
@test "bare hash with no digits -> exit 2, not silent auto-detect fallback" {
    run devx_pr_verify_live_parse "#"
    assert_failure 2
    assert_output --partial "PR# must be a positive integer: ''"
}

@test "remote-only + extra positional -> exit 2" {
    run devx_pr_verify_live_parse upstream extra
    assert_failure 2
    assert_output --partial "Unexpected positional arg: extra"
}

@test "-h -> help_requested" {
    run devx_pr_verify_live_parse -h
    assert_success
    assert_output --partial "help_requested=1"
}

@test "--help -> help_requested" {
    run devx_pr_verify_live_parse --help
    assert_success
    assert_output --partial "help_requested=1"
}

@test "help word -> help_requested" {
    run devx_pr_verify_live_parse help
    assert_success
    assert_output --partial "help_requested=1"
}

@test "combined flags resolve together" {
    run devx_pr_verify_live_parse 99 upstream --url http://127.0.0.1:3000 \
        --api-url=http://127.0.0.1:8080 --start "npm run dev" \
        --matrix full --viewports 1440,768,390 --locales ko,en --allow-remote-host \
        --no-comment
    assert_success
    assert_line "pr=99"
    assert_line "remote=upstream"
    assert_line "url=http://127.0.0.1:3000"
    assert_line "api_url=http://127.0.0.1:8080"
    assert_line "start_cmd=npm run dev"
    assert_line "matrix=full"
    assert_line "viewports=1440,768,390"
    assert_line "locales=ko,en"
    assert_line "issue_mode=create"
    assert_line "allow_remote_host=1"
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
    devx_pr_verify_live_parse 123 upstream >/dev/null
    [ "$pr" = "SENTINEL_PR" ]
    [ "$remote" = "SENTINEL_REMOTE" ]
}

@test "parse does not leak url/api_url/start_cmd/matrix into the caller's shell" {
    url="SENTINEL_URL"
    api_url="SENTINEL_API_URL"
    start_cmd="SENTINEL_START"
    matrix="SENTINEL_MATRIX"
    devx_pr_verify_live_parse --url http://127.0.0.1:3000 \
        --api-url http://127.0.0.1:8080 --start "npm run dev" \
        --matrix full >/dev/null
    [ "$url" = "SENTINEL_URL" ]
    [ "$api_url" = "SENTINEL_API_URL" ]
    [ "$start_cmd" = "SENTINEL_START" ]
    [ "$matrix" = "SENTINEL_MATRIX" ]
}

@test "parse does not leak viewports/locales/issue_mode/allow_remote_host/post_comment/_item" {
    viewports="SENTINEL_VIEWPORTS"
    locales="SENTINEL_LOCALES"
    issue_mode="SENTINEL_ISSUE_MODE"
    allow_remote_host="SENTINEL_ALLOW"
    post_comment="SENTINEL_POST_COMMENT"
    _rest="SENTINEL_REST"
    _item="SENTINEL_ITEM"
    devx_pr_verify_live_parse --viewports 1440,390 --locales ko,en \
        --dry-run --allow-remote-host --no-comment >/dev/null
    [ "$viewports" = "SENTINEL_VIEWPORTS" ]
    [ "$locales" = "SENTINEL_LOCALES" ]
    [ "$issue_mode" = "SENTINEL_ISSUE_MODE" ]
    [ "$allow_remote_host" = "SENTINEL_ALLOW" ]
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

@test "zsh: #1505 foreign-checkout guard warns when devx_pr_verify_live.sh is sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_zsh '. "$SHELL_COMMON/functions/devx_pr_verify_live.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_verify_live.sh"
}

@test "bash: #1505 foreign-checkout guard warns when devx_pr_verify_live.sh is sourced under bash" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_bash '. "$SHELL_COMMON/functions/devx_pr_verify_live.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/devx_pr_verify_live.sh"
}
