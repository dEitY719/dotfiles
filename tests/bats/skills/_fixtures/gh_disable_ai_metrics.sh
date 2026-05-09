#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_disable_ai_metrics.sh
# Source-of-truth mirror for the GH_DISABLE_AI_METRICS env-guard pattern
# documented in claude/skills/gh-issue-create/references/metrics-helper.md.
#
# The pattern is small but invariant across every gh:* skill that writes
# ai-metrics to GitHub — wrap the printf/gh-api call in:
#
#     if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
#         : # skip
#     else
#         <existing block>
#     fi
#
# This fixture mirrors that block in isolation so the bats suite catches
# behavioural drift (e.g. someone changing the comparison to a truthy
# coercion that opts unrelated values into skip).

# Append the footer to $1 (path to a temp body file). Returns 0 in both
# branches — the env-guard never blocks the surrounding flow (soft-fail).
gh_metrics_append_footer() {
    local _body="$1"
    if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
        : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
    else
        printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:test -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:test -->\n\n</details>\n' \
            1000 1 5 1000 1 5 >> "$_body"
    fi
}

# Convenience wrapper — creates a tempfile, appends, and cats the result
# so `run` can `assert_output --partial`. Cleans up the tempfile.
gh_metrics_append_footer_to_tempfile() {
    local _body
    _body=$(mktemp)
    gh_metrics_append_footer "$_body"
    cat "$_body"
    rm -f "$_body"
}
