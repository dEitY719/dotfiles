#!/usr/bin/env bats
# tests/bats/init/project_board_sync_workflow.bats
# Static sanity checks for `.github/workflows/project-board-sync.yml`.
# Behavioural correctness of the helpers it calls is covered in
# tests/bats/functions/gh_project_status.bats; here we only verify
# wiring — the workflow exists, triggers on the right event, calls the
# right helpers, and points at the PROJECT_BOARD_PAT secret.

load '../test_helper'

WORKFLOW="${DOTFILES_ROOT}/.github/workflows/project-board-sync.yml"

@test "workflow file exists" {
    [ -f "$WORKFLOW" ]
}

@test "triggers on pull_request closed events" {
    grep -q "^on:" "$WORKFLOW"
    grep -q "pull_request:" "$WORKFLOW"
    grep -q "types: \[closed\]" "$WORKFLOW"
}

@test "guards on merged == true (closed-without-merge skipped)" {
    grep -q "github.event.pull_request.merged == true" "$WORKFLOW"
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

@test "calls _gh_project_status_sync for the PR card" {
    grep -Eq '_gh_project_status_sync[[:space:]]+pr[[:space:]]+"\$PR_NUMBER"[[:space:]]+"Done"' "$WORKFLOW"
}

@test "iterates closingIssuesReferences via the shared helper" {
    # _gh_pr_closing_issue_numbers is the helper extracted in #264;
    # the workflow must use it instead of inlining `gh pr view --json
    # closingIssuesReferences` (which does not work on gh ≤ 2.45).
    grep -q '_gh_pr_closing_issue_numbers' "$WORKFLOW"
    ! grep -q 'gh pr view .* closingIssuesReferences' "$WORKFLOW"
}

@test "applies --only-from guard when moving Issue cards" {
    # Mirrors /gh-pr-merge Step 4(b): never bounce a card already at
    # "Approved" or "Done" backwards.
    grep -q -- '--only-from "Backlog,In progress,In review"' "$WORKFLOW"
}

@test "skips silently when PROJECT_BOARD_PAT is missing" {
    # Soft-fail: fork PRs and freshly forked clones have no access to
    # repo secrets. The workflow must warn and exit 0, not error.
    grep -q 'PROJECT_BOARD_PAT secret is not set' "$WORKFLOW"
}
