#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all_dedupe.bats
# Issue #1613 — the pre-dispatch duplicate-review guard.
#
# Step 3 now asks `devx_pr_review_all_already_reviewed <ai> <head-sha>` before
# dispatching each lane, and `--force-review` bypasses it. Fail-OPEN is the
# whole point here, the opposite of the verdict gate's fail-closed rule:
# anything short of a complete block for that exact ai+sha pair means "not yet
# reviewed", so the lane runs.
# Background + full rationale (SSOT):
# claude/skills/devx-pr-review-all/references/duplicate-review-guard.md
load '../test_helper'

setup() {
    # shellcheck disable=SC1090
    source "${DOTFILES_ROOT:?}/shell-common/functions/devx_pr_review_all.sh"
}

@test "already_reviewed: a block for this ai+sha -> already reviewed (rc 0)" {
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:agy:deadbeefdeadbeef -->
EOF
    assert_success
}

@test "already_reviewed: a block for a DIFFERENT sha -> not reviewed (rc 1)" {
    # The head moved since that review; the lane must run again.
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:0000111122223333 -->
Verdict: LGTM
<!-- /ai-review:agy:0000111122223333 -->
EOF
    assert_failure 1
}

@test "already_reviewed: a block for a DIFFERENT ai -> not reviewed (rc 1)" {
    # codex having reviewed this head says nothing about agy.
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:codex:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:codex:deadbeefdeadbeef -->
EOF
    assert_failure 1
}

@test "already_reviewed: no marker at all -> not reviewed (rc 1)" {
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
Thanks, LGTM from me.
Rebased onto main.
EOF
    assert_failure 1
}

@test "already_reviewed: empty stdin -> not reviewed (rc 1)" {
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef </dev/null
    assert_failure 1
}

@test "already_reviewed: an untagged block does not satisfy a sha request" {
    # A pre-#1564 comment carries no freshness claim, so it must not be read
    # as evidence that THIS head was reviewed.
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy -->
Verdict: LGTM
<!-- /ai-review:agy -->
EOF
    assert_failure 1
}

@test "already_reviewed: an unterminated block is not evidence" {
    # Half a review is not a review — the lane must run.
    run devx_pr_review_all_already_reviewed agy deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
EOF
    assert_failure 1
}

@test "already_reviewed: the right lane is found among several" {
    run devx_pr_review_all_already_reviewed codex deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:agy:deadbeefdeadbeef -->
<!-- ai-review:codex:deadbeefdeadbeef -->
판정: 블로킹
<!-- /ai-review:codex:deadbeefdeadbeef -->
EOF
    assert_success
}

@test "already_reviewed: a missing sha argument never claims 'reviewed'" {
    # Without a sha the wrapper cannot make a freshness claim, and guessing
    # would skip every re-review forever. Fail open instead.
    run devx_pr_review_all_already_reviewed agy <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:agy:deadbeefdeadbeef -->
EOF
    assert_failure 1
}

@test "already_reviewed: a missing ai argument never claims 'reviewed'" {
    run devx_pr_review_all_already_reviewed "" deadbeefdeadbeef <<'EOF'
<!-- ai-review:agy:deadbeefdeadbeef -->
Verdict: LGTM
<!-- /ai-review:agy:deadbeefdeadbeef -->
EOF
    assert_failure 1
}

@test "already_reviewed: usable as a plain if-guard in a pipeline" {
    # The documented Step 3 call shape: BODIES piped in, rc drives the skip.
    run bash -c '
        . "'"${DOTFILES_ROOT}"'/shell-common/functions/devx_pr_review_all.sh"
        BODIES="<!-- ai-review:agy:deadbeef -->
Verdict: LGTM
<!-- /ai-review:agy:deadbeef -->"
        for ai in agy codex; do
            if printf "%s\n" "$BODIES" | devx_pr_review_all_already_reviewed "$ai" deadbeef; then
                printf "SKIP %s\n" "$ai"
            else
                printf "RUN %s\n" "$ai"
            fi
        done'
    assert_success
    assert_line "SKIP agy"
    assert_line "RUN codex"
}

# ── accepted TOCTOU race (codex, PR #1623 BLOCKER) ──────────────────
# The guard is a read-before-write check, not a lock: two sessions reading the
# SAME pre-review BODIES snapshot before either one posts will both conclude
# "not yet reviewed" and both dispatch — exactly PR #1608's original failure,
# just with a narrower window. This test pins that as documented, accepted
# behavior (references/duplicate-review-guard.md -> "Known limitation"), not
# as a bug to fix here — a lock file was explicitly deprioritized in #1613.

@test "already_reviewed: two sessions racing on the same pre-review snapshot both see 'not reviewed'" {
    # Neither session has posted yet, so both read the identical empty-of-agy
    # BODIES. A lock would serialize this; the check does not.
    local shared_snapshot='Unrelated conversation comment.'

    run bash -c '
        . "'"${DOTFILES_ROOT}"'/shell-common/functions/devx_pr_review_all.sh"
        SNAPSHOT="'"$shared_snapshot"'"
        printf "%s\n" "$SNAPSHOT" | devx_pr_review_all_already_reviewed agy deadbeef
        session_a=$?
        printf "%s\n" "$SNAPSHOT" | devx_pr_review_all_already_reviewed agy deadbeef
        session_b=$?
        printf "session_a=%s session_b=%s\n" "$session_a" "$session_b"
    '
    assert_success
    assert_output --partial "session_a=1 session_b=1"
}

# ── doc guards ───────────────────────────────────────────────────────
# Same rule as the verdict suite's doc-guards: the SKILL step must CALL the
# shared helper by its literal call shape, not paraphrase the guard into prose
# an LLM can quietly skip.

@test "doc-guard: devx:pr-review-all Step 3 calls the shared dedupe helper" {
    run grep -qF -- 'devx_pr_review_all_already_reviewed "$ai" "$head_sha"' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "doc-guard: the SKILL documents the --force-review bypass" {
    run grep -qF -- '--force-review' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "doc-guard (#1623 agy BLOCKER): a guard-skipped lane must still be aggregated in Step 3.5" {
    run grep -qF -- 'each lane that actually ran' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_failure

    run grep -qF -- 'either ran fresh in Step 3 OR was skipped by the' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/SKILL.md"
    assert_success
}

@test "doc-guard (#1623 codex BLOCKER): the TOCTOU limitation is documented" {
    run grep -qF -- 'Known limitation: this is a check, not a lock' \
        "${DOTFILES_ROOT}/claude/skills/devx-pr-review-all/references/duplicate-review-guard.md"
    assert_success
}
