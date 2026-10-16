#!/usr/bin/env bats
# tests/bats/lint/gh_disable_ai_metrics_env_doc.bats
# Issue #399 — GH_DISABLE_AI_METRICS must stay registered in the env-var
# catalog. The guard's behaviour is tested where it ships:
# dEitY719/gh-issue-skills tests/bats/gh_disable_ai_metrics.bats against
# lib/ai-metrics-footer.sh (moved by #2200).

load '../test_helper'

@test "doc-guard: env-vars.md catalog registers GH_DISABLE_AI_METRICS" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/docs/.ssot/env-vars.md"
    [ -f "$f" ] || {
        echo "missing catalog: $f"
        return 1
    }
    run grep -F 'GH_DISABLE_AI_METRICS' "$f"
    assert_success
}
