#!/usr/bin/env bats
# tests/bats/skills/gh_disable_ai_metrics.bats
# Issue #399 — verify every gh:* skill that writes ai-metrics to GitHub
# carries the GH_DISABLE_AI_METRICS=1 short-circuit.
#
# Two layers:
#   1. Doc-level: each SKILL.md that calls `gh api ... comments`,
#      `gh issue create`, or appends a `<!-- ai-metrics:* -->` block
#      to a body file MUST contain the env-guard literal. Catches
#      future SKILL.md edits that forget to wrap a new metrics block.
#   2. Behavioural: a fixture mirrors the exact env-guard pattern from
#      the SSOT (gh-issue-create/references/metrics-helper.md). With
#      env unset/empty/!=1 the body is appended; with env=1 it is
#      skipped. Catches semantic drift in the guard itself.
#
# Backfill (gh-add-ai-metrics) is intentionally exempt — it ignores
# the env var by design (see issue #399 acceptance criteria).

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_disable_ai_metrics.sh"
}

teardown() {
    teardown_isolated_home
    unset GH_DISABLE_AI_METRICS
}

# -- Layer 1: doc-level env-guard presence -----------------------------------

# Every entry: <skill-dir>:<expected-substring-anchor> — anchor is something
# unique to that skill's metrics block so the test pinpoints the right region.
SKILLS_REQUIRING_GUARD=(
    "gh-issue-create"
    "gh-pr"
    "gh-commit"
    "gh-pr-reply"
    "gh-pr-approve"
    "gh-pr-merge"
    "gh-pr-merge-emergency"
    "gh-pr-resolve-conflict"
    "gh-issue-flow"
)

@test "doc-guard: every gh:* SKILL.md that writes ai-metrics has GH_DISABLE_AI_METRICS branch" {
    for skill in "${SKILLS_REQUIRING_GUARD[@]}"; do
        local f="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/${skill}/SKILL.md"
        run grep -F 'GH_DISABLE_AI_METRICS:-0' "$f"
        [ "$status" -eq 0 ] || {
            echo "missing GH_DISABLE_AI_METRICS guard in $f"
            return 1
        }
    done
}

@test "doc-guard: SSOT metrics-helper.md documents the env var" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-issue-create/references/metrics-helper.md"
    run grep -F 'GH_DISABLE_AI_METRICS' "$f"
    assert_success
    run grep -F 'gh-add-ai-metrics' "$f"
    assert_success
}

@test "doc-guard: gh-add-ai-metrics SKILL.md does NOT skip on the env var (backfill is explicit)" {
    # Backfill is the deliberate retrofit path; respecting the env there
    # would defeat the entire purpose of the tool. Verify it never adds
    # an opt-out branch by accident.
    local f="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-add-ai-metrics/SKILL.md"
    run grep -F 'GH_DISABLE_AI_METRICS' "$f"
    [ "$status" -ne 0 ] || {
        echo "gh-add-ai-metrics must not honor GH_DISABLE_AI_METRICS — backfill is explicit"
        return 1
    }
}

@test "doc-guard: env-vars.md catalog registers GH_DISABLE_AI_METRICS" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/docs/.ssot/env-vars.md"
    [ -f "$f" ] || {
        echo "missing catalog: $f"
        return 1
    }
    run grep -F 'GH_DISABLE_AI_METRICS' "$f"
    assert_success
}

# -- Layer 2: behavioural mirror of the SSOT guard ---------------------------

@test "behaviour: env unset → footer appended" {
    unset GH_DISABLE_AI_METRICS
    local body
    body=$(mktemp)
    run gh_metrics_append_footer "$body"
    assert_success
    run grep -c 'ai-metrics' "$body"
    [ "$output" -ge 2 ]
    rm -f "$body"
}

@test "behaviour: env empty → footer appended (treated as unset)" {
    GH_DISABLE_AI_METRICS="" run gh_metrics_append_footer_to_tempfile
    assert_success
    assert_output --partial 'ai-metrics:test'
}

@test "behaviour: env=0 → footer appended" {
    GH_DISABLE_AI_METRICS=0 run gh_metrics_append_footer_to_tempfile
    assert_success
    assert_output --partial 'ai-metrics:test'
}

@test "behaviour: env=1 → footer skipped, body untouched" {
    GH_DISABLE_AI_METRICS=1 run gh_metrics_append_footer_to_tempfile
    assert_success
    refute_output --partial 'ai-metrics'
    refute_output --partial 'AI Metrics'
}

@test "behaviour: env=2 → footer appended (only literal '1' opts out)" {
    # Guards against future drift to truthy-coercion that would silently
    # opt unrelated values into skip behaviour.
    GH_DISABLE_AI_METRICS=2 run gh_metrics_append_footer_to_tempfile
    assert_success
    assert_output --partial 'ai-metrics:test'
}

@test "behaviour: env=true → footer appended (only literal '1' opts out)" {
    GH_DISABLE_AI_METRICS=true run gh_metrics_append_footer_to_tempfile
    assert_success
    assert_output --partial 'ai-metrics:test'
}
