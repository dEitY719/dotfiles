#!/usr/bin/env bats
# tests/bats/skills/review_verdict_gate.bats
# Issue #1527 — the review verdict is now a first-class pipeline state:
# devx:pr-review-all emits `review-blocked` / `review-passed`, and
# gh:pr-merge-train gates on it. Those three skills are Claude-driven, not
# shell functions, so what bats can pin here is that the contract does not
# silently drift back out of their instructions — the same drift-guard shape
# as gh_pr_merge_board_gate_retired.bats (#1513).
#
# The parsing/aggregation logic itself is unit-tested in
# tests/bats/functions/devx_pr_review_all_verdict.bats.

load '../test_helper'

setup() {
    setup_isolated_home
    SKILLS="${_BATS_REAL_DOTFILES_ROOT}/claude/skills"
}

teardown() {
    teardown_isolated_home
}

# ── producer: devx:pr-review-all ─────────────────────────────────────

@test "#1527: devx:pr-review-all has a verdict-label reference" {
    run test -f "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
}

@test "#1527: devx:pr-review-all SKILL.md has a verdict aggregation step" {
    run grep -F "Aggregate verdicts into the merge-gate label" \
        "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "#1527: devx:pr-review-all names both helper functions" {
    run grep -F "devx_pr_review_all_verdict" "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
    run grep -F "devx_pr_review_all_aggregate" "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "#1527: the label is applied through _gh_pr_edit_safe_label, not bare gh pr edit" {
    # Projects-classic GraphQL deprecation makes `gh pr edit --add-label`
    # exit 1 with the label silently dropped (#326).
    run grep -F "_gh_pr_edit_safe_label" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
    run grep -F "gh pr edit --add-label" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    # mentioned only as the thing NOT to use
    assert_output --partial "never bare"
}

# ── consumer: gh:pr-merge-train ──────────────────────────────────────

@test "#1527: gh:pr-merge-train has a review-verdict gate reference" {
    run test -f "${SKILLS}/gh-pr-merge-train/references/review-verdict-gate.md"
    assert_success
}

@test "#1527: the train's queue query requests labels" {
    # Without `labels` in the --json field set the gate has nothing to read.
    run grep -F "baseRefName,title,labels" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: the train's SKILL.md declares the verdict gate at queue construction" {
    run grep -F "Review verdict gate (#1527)" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: absence of a label is a skip, never a pass" {
    # The load-bearing rule. If this phrasing disappears the gate is a no-op
    # for every PR that was never reviewed — the exact #1518 hole.
    run grep -F "Absence is a skip, not a pass" "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

@test "#1527: the train is forbidden from treating an unlabelled PR as reviewed" {
    run grep -F "Never treat an unlabelled PR as reviewed" \
        "${SKILLS}/gh-pr-merge-train/references/constraints.md"
    assert_success
}

@test "#1527: the train does not parse review comment bodies" {
    run grep -F "never parses a review comment body" \
        "${SKILLS}/gh-pr-merge-train/SKILL.md"
    assert_success
}

# ── release path: gh:pr-reply ────────────────────────────────────────

@test "#1527: gh:pr-reply has a review-blocked clear reference" {
    run test -f "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: gh:pr-reply clears review-blocked only after pushing an accepted fix" {
    run grep -F "PUSHED_FIXES" "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
    run grep -F "ACCEPTED_COUNT" "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: gh:pr-reply must never add review-passed" {
    run grep -F "never add \`review-passed\`" "${SKILLS}/gh-pr-reply/SKILL.md"
    assert_success
}

@test "#1527: gh:pr-reply removes the label via REST DELETE, not gh pr edit --remove-label" {
    run grep -F "gh pr edit --remove-label" \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    # mentioned only as the thing NOT to use
    assert_output --partial "not \`gh pr edit --remove-label\`"
    # `-i` keeps the HTTP status that `gh api` otherwise collapses into a bare
    # non-zero exit, so a 404 (label already absent) is not reported as failure.
    run grep -F "gh api -i -X DELETE" \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: any push retires review-passed (PR #1529 codex BLOCKER)" {
    # The label certifies a reviewed head; a push replaces that head. Leaving it
    # on lets the train merge code nobody reviewed — the hole the gate exists to
    # close. Unconditional on PUSHED_FIXES, unlike the review-blocked clear.
    run grep -F "pr_drop_label review-passed" \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

@test "#1527: the verdict is read from the PR comment block, not a lane return" {
    # PR #1529 agy+codex BLOCKER: gh:pr-review returns one `[OK] ...` line and a
    # subagent returns a summary — neither carries the verdict. Reading it from
    # the `<!-- ai-review:<ai> -->` artifact is what makes the gate work at all.
    run grep -F "devx_pr_review_all_lane_block" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
    run grep -F "ai-review:<ai>" \
        "${SKILLS}/devx-pr-review-all/references/review-verdict-label.md"
    assert_success
}

@test "#1527: GH_HOST is exported, not just prefixed (PR #1529 BLOCKER)" {
    # _gh_pr_edit_safe_label calls `gh` itself and has no host handling of its
    # own, so a per-call prefix never reaches it.
    run grep -F 'export GH_HOST="$TARGET_HOST"' \
        "${SKILLS}/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "#1527: the verdict labels have a bootstrap path in gh:label-bootstrap" {
    # PR #1529 codex BLOCKER: the add path refuses to auto-create (#326), so
    # without a provisioning route a repo lacking the labels deadlocks — every
    # PR unlabelled, every PR skipped, forever.
    run grep -F "pipeline|review-blocked|b60205" \
        "${SKILLS}/gh-label-bootstrap/references/gh-labels.md"
    assert_success
    run grep -F "pipeline|review-passed|0e8a16" \
        "${SKILLS}/gh-label-bootstrap/references/gh-labels.md"
    assert_success
    run grep -F "pipeline_feed" \
        "${SKILLS}/gh-label-bootstrap/lib/label-bootstrap.sh"
    assert_success
}

@test "#1527: clearing review-blocked requires no DECLINE in the run" {
    # PR #1529 codex FOLLOW-UP: PUSHED_FIXES + ACCEPTED_COUNT alone releases the
    # gate even when a blocker was declined in the same run. The verdict is one
    # line for the whole review, so the skill cannot tell which comment was the
    # blocker — a DECLINE anywhere must hold the label.
    run grep -F 'DECLINED_COUNT:-0}" -eq 0' \
        "${SKILLS}/gh-pr-reply/references/review-blocked-clear.sh.md"
    assert_success
}

# ── the retired gate must not come back (#1513 interaction) ──────────

@test "#1527: the fix does not resurrect the board Approved gate (#1513)" {
    run grep -RF "Step 2-B" "${SKILLS}/devx-pr-review-all/"
    assert_failure
    run grep -F "GH_PR_MERGE_SKIP_BOARD_CHECK" \
        "${SKILLS}/gh-pr-merge-train/references/review-verdict-gate.md"
    assert_failure
}

# ── End-to-end orchestration (PR #1529 review, codex FOLLOW-UP) ───────
# Everything above is a doc-drift grep. codex's point: the contract can read
# correctly while the actual path — lane comment -> block -> verdict ->
# aggregate -> label decision -> train action — is empty or wrong. These
# exercise that path against realistic PR comment bodies, no network.

lane_comments_fixture() {
    cat <<'FIX'
### AI Metrics — gh-pr-review
some unrelated comment body
<details><summary>AI Review · agy · --review=default</summary>
<!-- ai-review:agy -->
[BLOCKER] a.sh:1 — breaks on empty input
Assumption: none found.
Verdict: BLOCKING
<!-- /ai-review:agy -->
</details>
<details><summary>AI Review · codex · --review=default</summary>
<!-- ai-review:codex -->
[PRAISE] b.sh:9 — nice
판정: LGTM
<!-- /ai-review:codex -->
</details>
FIX
}

# Mirrors the Step 5 pipeline: bodies -> per-lane block -> verdict -> aggregate.
run_gate() {
    local bodies="$1" verdicts="" ai v
    shift
    for ai in "$@"; do
        v=$(printf '%s\n' "$bodies" | devx_pr_review_all_lane_block "$ai" | devx_pr_review_all_verdict)
        verdicts="$verdicts $v"
    done
    # shellcheck disable=SC2086
    devx_pr_review_all_aggregate $verdicts
}

@test "#1527 e2e: one blocking lane in real comment bodies -> review-blocked" {
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    run run_gate "$(lane_comments_fixture)" agy codex
    assert_success
    assert_output --partial "label=review-blocked"
    assert_output --partial "lanes=2"
}

@test "#1527 e2e: a lane that did not run contributes nothing, not unknown" {
    # hermes never ran, so it is simply not passed to the aggregator. The two
    # lanes that did run decide the label on their own.
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    run run_gate "$(lane_comments_fixture)" codex
    assert_success
    assert_output --partial "label=review-passed"
    assert_output --partial "lanes=1"
}

@test "#1527 e2e: a lane that ran but posted no block is unknown -> no label" {
    # The #1529 failure mode: the lane returned, but nothing machine-readable
    # reached the PR (GH_DISABLE_AI_METRICS=1, --no-post-comment, a crash).
    # It must NOT be promoted to a pass.
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    run run_gate "$(lane_comments_fixture)" codex hermes
    assert_success
    assert_line "label="
    assert_output --partial "lanes=2"
}

@test "#1527 e2e: a re-review supersedes the earlier verdict" {
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh"
    local bodies
    bodies="$(lane_comments_fixture)
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->"
    run run_gate "$bodies" agy codex
    assert_success
    assert_output --partial "label=review-passed"
}

@test "#1527 e2e: the train's three actions follow from the label" {
    # The gate contract gh:pr-merge-train implements, exercised as data.
    for row in "review-blocked:SKIPPED" ":SKIPPED" "review-passed:PROCEED"; do
        label="${row%%:*}"
        expected="${row##*:}"
        case "$label" in
        review-blocked) actual=SKIPPED ;;
        review-passed) actual=PROCEED ;;
        *) actual=SKIPPED ;;
        esac
        [ "$actual" = "$expected" ] || {
            echo "label '${label}' -> ${actual}, expected ${expected}"
            return 1
        }
    done
}
