#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all_verdict.bats
# Issue #1527 — the reviewer verdict ("판정: 블로킹" / "Verdict: BLOCKING")
# had no machine-readable consumer anywhere in the repo, so a PR carrying two
# independent blocking reviews (PR #1518) merged unchanged. These are the unit
# tests for the two pure helpers that turn lane output into the merge gate's
# first-class signal:
#
#   devx_pr_review_all_verdict    — one lane's raw output -> verdict token
#   devx_pr_review_all_aggregate  — N lane verdicts -> PR label (or none)
#
# Fail-closed is the whole point: "no label" must never be reachable from
# "everything passed", and "a lane ran but said nothing parseable" must never
# be promoted to a pass.
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_review_all.sh"
}

# ── devx_pr_review_all_verdict: Korean verdicts ──────────────────────

@test "verdict: Korean 블로킹 -> blocking" {
    run devx_pr_review_all_verdict <<'EOF'
[BLOCKER] a.sh:1 — breaks on empty input
판정: 블로킹
EOF
    assert_success
    assert_output "blocking"
}

@test "verdict: Korean 우려있음 -> concerns" {
    run devx_pr_review_all_verdict <<<"판정: 우려있음"
    assert_success
    assert_output "concerns"
}

@test "verdict: Korean LGTM -> lgtm" {
    run devx_pr_review_all_verdict <<<"판정: LGTM"
    assert_success
    assert_output "lgtm"
}

# ── devx_pr_review_all_verdict: English verdicts ─────────────────────

@test "verdict: English BLOCKING -> blocking" {
    run devx_pr_review_all_verdict <<<"Verdict: BLOCKING"
    assert_success
    assert_output "blocking"
}

@test "verdict: English CONCERNS -> concerns" {
    run devx_pr_review_all_verdict <<<"Verdict: CONCERNS"
    assert_success
    assert_output "concerns"
}

@test "verdict: English lgtm is case-insensitive" {
    run devx_pr_review_all_verdict <<<"verdict: lgtm"
    assert_success
    assert_output "lgtm"
}

# ── devx_pr_review_all_verdict: real-world noise ─────────────────────

@test "verdict: markdown bold + trailing detail still parses" {
    run devx_pr_review_all_verdict <<<"**판정: 블로킹 (BLOCKER 4건)**"
    assert_success
    assert_output "blocking"
}

@test "verdict: leading list dash still parses" {
    run devx_pr_review_all_verdict <<<"- Verdict: LGTM"
    assert_success
    assert_output "lgtm"
}

@test "verdict: the prompt template line is NOT a verdict" {
    # The preset prompt itself contains `판정: [LGTM|우려있음|블로킹]`. A lane
    # that echoes its own instructions back must not be read as an LGTM.
    run devx_pr_review_all_verdict <<<"판정: [LGTM|우려있음|블로킹]"
    assert_success
    assert_output "unknown"
}

@test "verdict: a bracket in the detail text is not a template echo" {
    # Only a value that *opens* with `[` is the preset template. A bracketed
    # count after a real verdict must still parse — dropping it would leave
    # the PR unlabelled and silently un-mergeable.
    run devx_pr_review_all_verdict <<<"판정: 블로킹 [BLOCKER 4건]"
    assert_success
    assert_output "blocking"
}

@test "verdict: last verdict line wins" {
    run devx_pr_review_all_verdict <<'EOF'
판정: LGTM
판정: 블로킹
EOF
    assert_success
    assert_output "blocking"
}

@test "verdict: a BLOCKER finding alone is not a verdict" {
    # Findings are classified [BLOCKER|FOLLOW-UP|PRAISE]; only the mandatory
    # last verdict line decides the lane. No verdict line -> unknown.
    run devx_pr_review_all_verdict <<<"[BLOCKER] a.sh:1 — breaks on empty input"
    assert_success
    assert_output "unknown"
}

@test "verdict: empty lane output -> unknown" {
    run devx_pr_review_all_verdict </dev/null
    assert_success
    assert_output "unknown"
}

@test "verdict: unrecognized verdict value -> unknown" {
    run devx_pr_review_all_verdict <<<"Verdict: MAYBE"
    assert_success
    assert_output "unknown"
}

# ── devx_pr_review_all_aggregate ─────────────────────────────────────

@test "aggregate: one blocking lane -> review-blocked" {
    run devx_pr_review_all_aggregate lgtm blocking
    assert_success
    assert_output --partial "label=review-blocked"
}

@test "aggregate: all lanes pass -> review-passed" {
    run devx_pr_review_all_aggregate lgtm concerns
    assert_success
    assert_output --partial "label=review-passed"
}

@test "aggregate: zero lanes ran -> no label" {
    run devx_pr_review_all_aggregate
    assert_success
    assert_line "label="
}

@test "aggregate: an unknown lane is never promoted to a pass" {
    run devx_pr_review_all_aggregate lgtm unknown
    assert_success
    assert_line "label="
}

@test "aggregate: blocking outranks unknown" {
    run devx_pr_review_all_aggregate unknown blocking
    assert_success
    assert_output --partial "label=review-blocked"
}

@test "aggregate: garbage token is treated as unknown, not a pass" {
    run devx_pr_review_all_aggregate lgtm ohai
    assert_success
    assert_line "label="
}

@test "aggregate: reports the lane count it decided on" {
    run devx_pr_review_all_aggregate lgtm concerns blocking
    assert_success
    assert_output --partial "lanes=3"
}
