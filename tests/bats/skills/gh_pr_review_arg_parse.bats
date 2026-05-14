#!/usr/bin/env bats
# tests/bats/skills/gh_pr_review_arg_parse.bats
# Verify the Step 1 arg-parsing + Step 3 preset-normalization logic
# documented in claude/skills/gh-pr-review/SKILL.md.
# Source-of-truth fixture: _fixtures/gh_pr_review_arg_parse.sh.
#
# Covers issue #637's Acceptance Criteria:
#   - --ai required, single value, allowed enum
#   - --review default, allowed enum, KR alias normalization, exit 2 on unknown
#   - --user is claude-only (cross-AI rejection)
#   - --no-post-comment flag
#   - help passthrough (-h / --help / help)

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh"
}

teardown() {
    teardown_isolated_home
}

# ---- --ai gate -------------------------------------------------------------

@test "ai: missing --ai → exit 2 + 'missing required flag'" {
    run gh_pr_review_parse 99
    assert_failure 2
    assert_output --partial "missing required flag: --ai"
}

@test "ai: unknown --ai value → exit 2 + allowed list" {
    run gh_pr_review_parse --ai chatgpt 99
    assert_failure 2
    assert_output --partial "Unknown --ai value: 'chatgpt'"
    assert_output --partial "allowed: codex, gemini, claude"
}

@test "ai: --ai codex → ok, ai=codex" {
    run gh_pr_review_parse --ai codex 99
    assert_success
    assert_output --partial "ai=codex"
    assert_output --partial "pr=99"
}

@test "ai: --ai=gemini (= form) → ok, ai=gemini" {
    run gh_pr_review_parse --ai=gemini 99
    assert_success
    assert_output --partial "ai=gemini"
}

@test "ai: --ai claude → ok, ai=claude" {
    run gh_pr_review_parse --ai claude 99
    assert_success
    assert_output --partial "ai=claude"
}

# ---- --review enum + KR alias ---------------------------------------------

@test "review: default when omitted" {
    run gh_pr_review_parse --ai codex 99
    assert_success
    assert_output --partial "review=default"
}

@test "review: explicit --review thorough → ok" {
    run gh_pr_review_parse --ai codex --review thorough 99
    assert_success
    assert_output --partial "review=thorough"
}

@test "review: KR alias 보통 → default" {
    run gh_pr_review_parse --ai codex --review 보통 99
    assert_success
    assert_output --partial "review=default"
}

@test "review: KR alias 간단 → quick" {
    run gh_pr_review_parse --ai codex --review 간단 99
    assert_success
    assert_output --partial "review=quick"
}

@test "review: KR alias 꼼꼼 → thorough" {
    run gh_pr_review_parse --ai codex --review 꼼꼼 99
    assert_success
    assert_output --partial "review=thorough"
}

@test "review: KR alias 꼼꼼하게 → thorough" {
    run gh_pr_review_parse --ai claude --review 꼼꼼하게 99
    assert_success
    assert_output --partial "review=thorough"
}

@test "review: KR alias 보안 → security" {
    run gh_pr_review_parse --ai gemini --review 보안 99
    assert_success
    assert_output --partial "review=security"
}

@test "review: KR alias 성능 → performance" {
    run gh_pr_review_parse --ai gemini --review 성능 99
    assert_success
    assert_output --partial "review=performance"
}

@test "review: unknown --review value → exit 2 + allowed enum" {
    run gh_pr_review_parse --ai codex --review unknown 99
    assert_failure 2
    assert_output --partial "Unknown --review value: 'unknown'"
    assert_output --partial "Allowed: default | quick | thorough | security | performance"
    assert_output --partial "Korean aliases"
}

@test "review: free-text rejected even when it 'sounds' valid" {
    # The skill explicitly rejects free text — only the 5 enum +
    # 5 KR aliases above pass.
    run gh_pr_review_parse --ai claude --review "꼼꼼하게 봐줘" 99
    assert_failure 2
    assert_output --partial "Unknown --review value"
}

# ---- --user gate (claude-only) --------------------------------------------

@test "user: --user with --ai codex → exit 2 (cross-AI rejected)" {
    run gh_pr_review_parse --ai codex --user work 99
    assert_failure 2
    assert_output --partial "--user is only valid with --ai claude"
}

@test "user: --user with --ai gemini → exit 2 (cross-AI rejected)" {
    run gh_pr_review_parse --ai gemini --user work 99
    assert_failure 2
    assert_output --partial "--user is only valid with --ai claude"
}

@test "user: --user work with --ai claude → ok, user=work" {
    run gh_pr_review_parse --ai claude --user work 99
    assert_success
    assert_output --partial "user=work"
}

@test "user: --user omitted → empty (preserve current shell CLAUDE_CONFIG_DIR)" {
    run gh_pr_review_parse --ai claude 99
    assert_success
    assert_output --partial "user="
    refute_output --partial "user=personal"
}

# ---- --no-post-comment + positional args ---------------------------------

@test "post-comment: default ON (post_comment=1)" {
    run gh_pr_review_parse --ai codex 99
    assert_success
    assert_output --partial "post_comment=1"
}

@test "post-comment: --no-post-comment flag → post_comment=0" {
    run gh_pr_review_parse --ai codex --no-post-comment 99
    assert_success
    assert_output --partial "post_comment=0"
}

@test "positional: pr-number + remote → pr=99, remote=upstream" {
    run gh_pr_review_parse --ai codex 99 upstream
    assert_success
    assert_output --partial "pr=99"
    assert_output --partial "remote=upstream"
}

@test "positional: remote defaults to origin" {
    run gh_pr_review_parse --ai codex 99
    assert_success
    assert_output --partial "remote=origin"
}

# ---- help passthrough -----------------------------------------------------

@test "help: -h short flag → help_requested=1, no parse" {
    run gh_pr_review_parse -h
    assert_success
    assert_output "help_requested=1"
}

@test "help: --help long flag → help_requested=1" {
    run gh_pr_review_parse --help
    assert_success
    assert_output "help_requested=1"
}

@test "help: 'help' literal → help_requested=1" {
    run gh_pr_review_parse help
    assert_success
    assert_output "help_requested=1"
}
