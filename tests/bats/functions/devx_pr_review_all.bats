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

@test "no --force-review -> force_review=0 (guard armed by default)" {
    run devx_pr_review_all_parse 123
    assert_success
    assert_line "force_review=0"
}

@test "--force-review -> force_review=1" {
    run devx_pr_review_all_parse 123 --force-review
    assert_success
    assert_line "force_review=1"
}

@test "--force-review combines with --defer-reply" {
    run devx_pr_review_all_parse 123 --defer-reply 8 --force-review
    assert_success
    assert_line "force_review=1"
    assert_output --partial "reply_mode=defer"
    assert_output --partial "reply_delay=8"
}

@test "--force-review combines with a remote positional" {
    run devx_pr_review_all_parse 123 upstream --force-review
    assert_success
    assert_line "force_review=1"
    assert_output --partial "remote=upstream"
}

# ── gh-verify-skills#56: multi-preset review lanes (--lanes) ──────────
# The flag names one `<ai>:<preset>` lane per comma-separated entry. Omitting
# it must reproduce today's four-lane fan-out exactly — that is the whole
# backward-compatibility claim — and a malformed value must fail loudly
# instead of quietly dispatching fewer lanes than asked for.

@test "--lanes omitted -> the legacy four default lanes" {
    run devx_pr_review_all_parse 123
    assert_success
    assert_line "lanes=agy:default,codex:default,opencode:default,hermes:default"
}

@test "--lanes takes a two-preset fan-out of the same AI" {
    run devx_pr_review_all_parse 123 --lanes "opencode:default,opencode:thorough"
    assert_success
    assert_line "lanes=opencode:default,opencode:thorough"
}

@test "--lanes= form is equivalent" {
    run devx_pr_review_all_parse 123 --lanes=hermes:security
    assert_success
    assert_line "lanes=hermes:security"
}

@test "--lanes accepts agy/codex without special-casing them" {
    # Multi-preset for these two is out of scope for cost reasons, but that is
    # a policy the caller applies — the parser must not encode it.
    run devx_pr_review_all_parse 123 --lanes "agy:thorough,codex:security"
    assert_success
    assert_line "lanes=agy:thorough,codex:security"
}

@test "--lanes with no value -> exit 2" {
    run devx_pr_review_all_parse 123 --lanes
    assert_failure 2
}

@test "--lanes entry without a preset -> exit 2 (never a silent default)" {
    run devx_pr_review_all_parse 123 --lanes "opencode"
    assert_failure 2
    assert_output --partial "<ai>:<preset>"
}

@test "--lanes entry with a third field -> exit 2" {
    run devx_pr_review_all_parse 123 --lanes "opencode:thorough:extra"
    assert_failure 2
}

@test "--lanes empty value -> exit 2 (zero lanes is not a fan-out)" {
    run devx_pr_review_all_parse 123 --lanes ""
    assert_failure 2
}

@test "--lanes with an empty entry (trailing comma) -> exit 2" {
    run devx_pr_review_all_parse 123 --lanes "opencode:default,"
    assert_failure 2
}

@test "--lanes empty ai or empty preset -> exit 2" {
    run devx_pr_review_all_parse 123 --lanes ":default"
    assert_failure 2
    run devx_pr_review_all_parse 123 --lanes "opencode:"
    assert_failure 2
}

@test "--lanes repeated entry -> exit 2 (the dup would be deduped away)" {
    # The #1613 guard would skip the second copy once the first posts, so
    # accepting it would dispatch fewer lanes than the report claims.
    run devx_pr_review_all_parse 123 --lanes "opencode:default,opencode:default"
    assert_failure 2
    assert_output --partial "repeated"
}

@test "--lanes rejects a Korean --review alias (it would break the marker)" {
    # `gh-pr:review` normalizes 꼼꼼 -> thorough, so the lane would post a
    # `thorough` marker this skill (still looking for 꼼꼼) could never find.
    run devx_pr_review_all_parse 123 --lanes "opencode:꼼꼼"
    assert_failure 2
}

@test "--lanes with a space in an entry -> exit 2" {
    run devx_pr_review_all_parse 123 --lanes "opencode:thor ough"
    assert_failure 2
}

@test "--lanes combines with the other flags" {
    run devx_pr_review_all_parse 123 upstream --lanes "hermes:performance" --force-review --defer-reply 8
    assert_success
    assert_line "lanes=hermes:performance"
    assert_line "force_review=1"
    assert_output --partial "remote=upstream"
    assert_output --partial "reply_mode=defer"
}

@test "help flag -> help_requested" {
    run devx_pr_review_all_parse --help
    assert_success
    assert_output --partial "help_requested=1"
}

@test "parse does not leak pr/remote/reply_mode/reply_delay/_no_reply/_remote_set/_force_review/lanes into the caller's shell" {
    pr="SENTINEL_PR"
    remote="SENTINEL_REMOTE"
    reply_mode="SENTINEL_REPLY_MODE"
    reply_delay="SENTINEL_REPLY_DELAY"
    _no_reply="SENTINEL_NO_REPLY"
    _remote_set="SENTINEL_REMOTE_SET"
    _force_review="SENTINEL_FORCE_REVIEW"
    lanes="SENTINEL_LANES"
    _lane_rest="SENTINEL_LANE_REST"
    _lane_item="SENTINEL_LANE_ITEM"
    _lane_ai="SENTINEL_LANE_AI"
    _lane_preset="SENTINEL_LANE_PRESET"
    _lane_seen="SENTINEL_LANE_SEEN"
    devx_pr_review_all_parse 123 upstream --defer-reply 8 --force-review \
        --lanes "opencode:default,opencode:thorough" >/dev/null
    _rc=$?
    [ "$_rc" -eq 0 ]
    [ "$pr" = "SENTINEL_PR" ]
    [ "$remote" = "SENTINEL_REMOTE" ]
    [ "$reply_mode" = "SENTINEL_REPLY_MODE" ]
    [ "$reply_delay" = "SENTINEL_REPLY_DELAY" ]
    [ "$_no_reply" = "SENTINEL_NO_REPLY" ]
    [ "$_remote_set" = "SENTINEL_REMOTE_SET" ]
    [ "$_force_review" = "SENTINEL_FORCE_REVIEW" ]
    [ "$lanes" = "SENTINEL_LANES" ]
    [ "$_lane_rest" = "SENTINEL_LANE_REST" ]
    [ "$_lane_item" = "SENTINEL_LANE_ITEM" ]
    [ "$_lane_ai" = "SENTINEL_LANE_AI" ]
    [ "$_lane_preset" = "SENTINEL_LANE_PRESET" ]
    [ "$_lane_seen" = "SENTINEL_LANE_SEEN" ]
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
