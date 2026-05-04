#!/usr/bin/env bats
# tests/bats/init/project_board_sync_workflow.bats
# Static sanity checks for `.github/workflows/project-board-sync.yml`.
# Behavioural correctness of the helpers it calls is covered in
# tests/bats/functions/gh_project_status.bats; here we only verify
# wiring — the workflow exists, triggers on the right events, calls the
# right helpers with the right guards, and points at the PROJECT_BOARD_PAT
# secret.

load '../test_helper'

WORKFLOW="${DOTFILES_ROOT}/.github/workflows/project-board-sync.yml"

@test "workflow file exists" {
    [ -f "$WORKFLOW" ]
}

@test "triggers on pull_request closed events" {
    grep -q "^on:" "$WORKFLOW"
    grep -q "pull_request:" "$WORKFLOW"
    grep -qE "types:.*closed" "$WORKFLOW"
}

@test "triggers on pull_request opened, ready_for_review, and reopened events" {
    grep -qE "types:.*opened" "$WORKFLOW"
    grep -qE "types:.*ready_for_review" "$WORKFLOW"
    grep -qE "types:.*reopened" "$WORKFLOW"
}

@test "triggers on pull_request_review submitted events" {
    grep -q "pull_request_review:" "$WORKFLOW"
    grep -qE "types:.*\[submitted\]" "$WORKFLOW"
}

@test "guards on merged == true (closed-without-merge skipped)" {
    grep -q "github.event.pull_request.merged == true" "$WORKFLOW"
}

@test "guards PR review approved step on review.state == approved" {
    grep -q "github.event.review.state == 'approved'" "$WORKFLOW"
}

@test "uses PROJECT_BOARD_PAT secret (not the default GITHUB_TOKEN)" {
    # projectV2 mutation requires the `project` scope, which the default
    # GITHUB_TOKEN cannot grant. The workflow must read PAT from secrets.
    grep -q 'secrets.PROJECT_BOARD_PAT' "$WORKFLOW"
}

@test "sources the shared gh_project_status.sh helper" {
    # SSOT: the workflow must reuse the same helper /gh-pr-merge uses,
    # not inline a copy.
    grep -q 'shell-common/functions/gh_project_status.sh' "$WORKFLOW"
}

@test "PR opened step: syncs PR card to In review" {
    grep -Eq '_gh_project_status_sync[[:space:]]+pr[[:space:]]+"\$PR_NUMBER"[[:space:]]+"In review"' "$WORKFLOW"
}

@test "PR opened step: syncs linked Issues to In progress with Backlog,Ready guard" {
    # Issues must not visit "In review" — the opened step immediately corrects
    # the builtin "Pull request linked to issue" workflow that would move them there.
    grep -q '_gh_project_status_sync issue' "$WORKFLOW"
    grep -q -- '--only-from "Backlog,Ready"' "$WORKFLOW"
}

@test "PR review approved step: syncs PR card to Approved" {
    grep -Eq '_gh_project_status_sync[[:space:]]+pr[[:space:]]+"\$PR_NUMBER"[[:space:]]+"Approved"' "$WORKFLOW"
}

@test "PR merged step: calls _gh_project_status_sync for the PR card to Done" {
    grep -Eq '_gh_project_status_sync[[:space:]]+pr[[:space:]]+"\$PR_NUMBER"[[:space:]]+"Done"' "$WORKFLOW"
}

@test "iterates closingIssuesReferences via the shared helper" {
    # _gh_pr_closing_issue_numbers is the helper extracted in #264;
    # the workflow must use it instead of inlining `gh pr view --json
    # closingIssuesReferences` (which does not work on gh ≤ 2.45).
    grep -q '_gh_pr_closing_issue_numbers' "$WORKFLOW"
    ! grep -q 'gh pr view .* closingIssuesReferences' "$WORKFLOW"
}

@test "applies --only-from guard when moving Issue cards to Done" {
    # Mirrors /gh-pr-merge Step 4(b): never bounce a card already at Done
    # backwards. "In review" kept as a safety net for the transition period.
    grep -q -- '--only-from "Backlog,In progress,In review"' "$WORKFLOW"
}

@test "fork PRs without the PAT soft-skip with a warning" {
    # GitHub does not pass repo secrets to fork PR runs. The guard step
    # must warn-and-exit-0 in that case so external contributors do not
    # get red CI for a sync they cannot perform.
    grep -q '::warning::PROJECT_BOARD_PAT not available for fork PR' "$WORKFLOW"
}

@test "canonical PRs without the PAT fail loudly with an actionable error" {
    # Regression guard for #289 / #300: prior revision warned-and-exit-0
    # on the canonical repo too, so the workflow silently no-op'd from
    # PR #290 merge until detection. Now the missing-secret case must
    # error-and-exit-1 on the canonical repo so a misconfigured setup
    # cannot ride along undetected.
    grep -q '::error::PROJECT_BOARD_PAT secret is missing' "$WORKFLOW"
    grep -q 'gh secret set PROJECT_BOARD_PAT' "$WORKFLOW"
}

@test "guard step runs first and discriminates fork vs canonical via PR_HEAD_REPO" {
    # The guard step must compare github.event.pull_request.head.repo.full_name
    # against github.repository — equality means same-repo PR (PAT must
    # exist), inequality means fork PR (soft-skip is correct).
    grep -q 'PR_HEAD_REPO:' "$WORKFLOW"
    grep -q 'github.event.pull_request.head.repo.full_name' "$WORKFLOW"
    # Pin the intent (PR_HEAD_REPO is compared inequality-wise to GH_REPO),
    # not the quoting or brace style. Tolerates rewrites like
    # ${PR_HEAD_REPO}, $PR_HEAD_REPO, "${PR_HEAD_REPO:-}", etc.
    grep -Eq 'PR_HEAD_REPO[^!]*!=[[:space:]]*"?\$\{?GH_REPO' "$WORKFLOW"
}
