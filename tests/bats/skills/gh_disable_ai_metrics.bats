#!/usr/bin/env bats
# tests/bats/skills/gh_disable_ai_metrics.bats
# Issue #399 — verify every gh:* skill that writes ai-metrics to GitHub
# carries the GH_DISABLE_AI_METRICS=1 short-circuit.
#
# What is left here after #1680:
#   1. The env-vars.md catalog registration (docs/.ssot lives in this repo).
#   2. Behavioural: a fixture mirrors the env-guard pattern. With env
#      unset/empty/!=1 the body is appended; with env=1 it is skipped.
#      Catches semantic drift in the guard itself.
#
# #1680: the gh:* skills moved out to their own marketplace repos, so the
# three doc-guards that grepped claude/skills/** (per-SKILL.md guard
# presence, the metrics-helper.md SSOT, and the gh-add-ai-metrics
# backfill exemption) were dropped and belong in those repos now. The
# fixture below is consequently no longer pinned to the SSOT doc.

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

# -- Layer 1: catalog registration -------------------------------------------

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
