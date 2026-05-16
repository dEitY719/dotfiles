#!/usr/bin/env bats
# tests/bats/functions/gh_pr_review.bats
# Coverage for the production shell function `gh_pr_review` introduced
# in issue #664. Exercises the deterministic surface (loading, help,
# require_ai_cli, prompt builder, comment body builder, post-comment
# guards) without invoking real AI CLIs or the live GitHub API.
#
# The Step 1 arg-parser is already covered by
# tests/bats/skills/gh_pr_review_arg_parse.bats (the fixture now
# sources this same production file); this suite does NOT duplicate
# those cases — it covers what the fixture cannot.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Source the production module directly into the bats shell. The
# interactive guard would normally short-circuit, but DOTFILES_FORCE_INIT
# (set by test_helper) bypasses it. This is the same pattern the
# fixture uses, so loading semantics stay aligned.
_source_module() {
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh"
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "bash: gh_pr_review function exists after sourcing" {
    run_in_bash 'declare -f gh_pr_review >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-pr-review alias resolves to gh_pr_review" {
    run_in_bash "alias gh-pr-review 2>/dev/null | grep -q gh_pr_review && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_pr_review function exists after sourcing" {
    run_in_zsh 'typeset -f gh_pr_review >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Help surface (bypasses all preconditions)
# ---------------------------------------------------------------------------

@test "bash: no args prints help" {
    run_in_bash 'gh_pr_review'
    assert_success
    assert_output --partial "gh-pr-review"
    assert_output --partial "--ai"
}

@test "bash: --help prints help with usage block" {
    run_in_bash 'gh_pr_review --help'
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gh-pr-review --ai"
}

@test "bash: -h prints help" {
    run_in_bash 'gh_pr_review -h'
    assert_success
    assert_output --partial "Usage:"
}

@test "bash: help documents all five review presets" {
    # The closed enum is part of the user contract. If any preset is
    # ever silently dropped, /gh-pr-review --review <preset> still
    # 'works' but the helper can no longer route correctly. Catch the
    # drift at help generation time.
    run_in_bash 'gh_pr_review --help'
    assert_success
    assert_output --partial "default"
    assert_output --partial "quick"
    assert_output --partial "thorough"
    assert_output --partial "security"
    assert_output --partial "performance"
}

# ---------------------------------------------------------------------------
# _gh_pr_review_require_ai_cli — PATH pre-flight
# ---------------------------------------------------------------------------

@test "require_ai_cli: unknown value → exit 2" {
    _source_module
    run _gh_pr_review_require_ai_cli chatgpt
    assert_failure 2
    assert_output --partial "Unknown --ai value: 'chatgpt'"
}

@test "require_ai_cli: missing CLI → exit 1 with canonical message" {
    # Force an empty PATH so no AI CLI can possibly be found. The bash
    # builtins still resolve because `command -v` is a shell builtin.
    _source_module
    PATH="" run _gh_pr_review_require_ai_cli codex
    assert_failure 1
    assert_output --partial "Required CLI 'codex' not found in PATH"
}

@test "require_ai_cli: present CLI → exit 0" {
    # Stage a stub `codex` binary in a sandbox PATH so we can verify the
    # success branch without depending on whatever the host has installed.
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$stub_dir/codex"
    PATH="$stub_dir:$PATH" run _gh_pr_review_require_ai_cli codex
    assert_success
}

# ---------------------------------------------------------------------------
# Prompt builder — preset selection + diff section
# ---------------------------------------------------------------------------

# Stub `gh` so `_gh_pr_review_build_prompt` can exercise its diff-fetch
# branch without reaching the live GitHub API. The builder tolerates a
# non-zero `gh pr diff` exit (`|| true`), so the stub is allowed to be
# a no-op; the framing markers must still land in the output file.
_stub_gh_noop() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$stub_dir/gh"
    export PATH="$stub_dir:$PATH"
}

@test "build_prompt: default preset writes 7-dimension body + diff markers" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-default.txt"
    _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature
    [ -f "$out" ]
    run grep -q "second-opinion reviewer" "$out"
    assert_success
    run grep -q "7 dimensions" "$out"
    assert_success
    run grep -q "PR DIFF (PR #99, repo owner/repo" "$out"
    assert_success
    run grep -q "END PR DIFF" "$out"
    assert_success
}

@test "build_prompt: quick preset routes to BLOCKER-only body" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-quick.txt"
    _gh_pr_review_build_prompt quick "$out" 1 a/b base head
    run grep -q "ONLY surface BLOCKER findings" "$out"
    assert_success
}

@test "build_prompt: security preset routes to security-lens body" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-sec.txt"
    _gh_pr_review_build_prompt security "$out" 2 a/b base head
    run grep -q "Security-focused review" "$out"
    assert_success
}

@test "build_prompt: unknown preset returns exit 2" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-bad.txt"
    run _gh_pr_review_build_prompt unknown "$out" 1 a/b base head
    assert_failure 2
}

# ---------------------------------------------------------------------------
# Token estimator
# ---------------------------------------------------------------------------

@test "estimate_tokens: tiny file rounds up to floor 1000" {
    _source_module
    local f="$TEST_TEMP_HOME/tiny.txt"
    printf 'hi' >"$f"
    run _gh_pr_review_estimate_tokens "$f"
    assert_success
    assert_output "1000"
}

@test "estimate_tokens: large file rounds to nearest 500" {
    _source_module
    local f="$TEST_TEMP_HOME/big.txt"
    # ~12 000 bytes → ~3000 tokens.
    yes "abcd1234" | head -c 12000 >"$f"
    run _gh_pr_review_estimate_tokens "$f"
    assert_success
    # Allow a ±500 wobble since the rounding boundary is on 500.
    [[ "$output" =~ ^[23][05]00$ ]]
}

# ---------------------------------------------------------------------------
# Comment body builder — required SSOT markers
# ---------------------------------------------------------------------------

@test "build_comment_body: contains ai-review + ai-metrics markers" {
    _source_module
    local out="$TEST_TEMP_HOME/body.md"
    local ai_out="$TEST_TEMP_HOME/ai-out.txt"
    printf '[BLOCKER] foo.sh:1 — bar\n' >"$ai_out"
    _gh_pr_review_build_comment_body "$out" codex thorough "$ai_out" 2500 2.5 7
    run cat "$out"
    assert_success
    assert_output --partial "AI Review · codex · --review=thorough"
    assert_output --partial "<!-- ai-review:codex -->"
    assert_output --partial "<!-- /ai-review:codex -->"
    assert_output --partial "<!-- ai-metrics:gh-pr-review -->"
    assert_output --partial "📊 ~2500 tokens · 👤 ~2.5 h · 🤖 ~7 min"
    assert_output --partial "[BLOCKER] foo.sh:1"
}

@test "human_h baseline: each preset returns the documented value" {
    _source_module
    run _gh_pr_review_human_h quick;       assert_output "0.3"
    run _gh_pr_review_human_h default;     assert_output "1.0"
    run _gh_pr_review_human_h thorough;    assert_output "2.5"
    run _gh_pr_review_human_h security;    assert_output "1.5"
    run _gh_pr_review_human_h performance; assert_output "1.5"
}

# ---------------------------------------------------------------------------
# Post-comment guards (skip paths) + soft-fail
# ---------------------------------------------------------------------------

@test "post_comment: --no-post-comment (post=0) → skipped, exit 0" {
    _source_module
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    run _gh_pr_review_post_comment 99 owner/repo "$body" 0
    assert_success
    assert_output --partial "skipped (--no-post-comment)"
}

@test "post_comment: GH_DISABLE_AI_METRICS=1 → entire comment skipped, exit 0" {
    _source_module
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    GH_DISABLE_AI_METRICS=1 run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "skipped (GH_DISABLE_AI_METRICS=1)"
}

@test "post_comment: gh failure → soft-fail exit 0 + [WARN] line" {
    _source_module
    # Stage a stub `gh` that always fails so the post step exercises its
    # soft-fail branch. The function must NOT propagate the non-zero
    # exit — the AI output is already on the user's stdout.
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
echo "simulated gh failure" >&2
exit 1
EOF
    chmod +x "$stub_dir/gh"
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    PATH="$stub_dir:$PATH" run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "[WARN] post failed"
}

@test "post_comment: gh success → URL returned, exit 0" {
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
echo "https://github.com/owner/repo/pull/99#issuecomment-1"
exit 0
EOF
    chmod +x "$stub_dir/gh"
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    PATH="$stub_dir:$PATH" run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "issuecomment-1"
}
