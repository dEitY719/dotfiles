#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_reply_auto_approve.sh
# Source-of-truth mirror for the Step 8 (Solo-Repo Auto-Approve) gating
# logic documented in claude/skills/gh-pr-reply/references/auto-approve.md.
#
# The skill itself runs inside a Claude session, but the gating logic is
# a small POSIX block that can be tested in isolation: given the four
# guard inputs (allowlist env var, repo, comment count, PR state, draft
# flag, reviewDecision) and a stub helper, does Step 8 fire (call helper
# + audit-trace) or skip (one info line, no helper call)?
#
# Keep this file in sync with references/auto-approve.md. If the policy
# block changes, mirror the change here so the bats suite catches drift.

# Stand-in for _gh_project_status_sync. The real helper lives in
# shell-common/functions/gh_project_status.sh; tests inject behaviour via
# FAKE_HELPER_RC and FAKE_HELPER_LOG. Records its bypass arg and full
# argv to FAKE_HELPER_LOG so assertions can verify both the call shape
# and that the bypass env var was scoped to this call only.
_gh_project_status_sync() {
    : "${FAKE_HELPER_LOG:?FAKE_HELPER_LOG must be set by the test}"
    printf 'helper called bypass=%s args=%s\n' \
        "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-}" "$*" \
        >> "$FAKE_HELPER_LOG"
    return "${FAKE_HELPER_RC-0}"
}

# Mirrors auto-approve.md's algorithm verbatim. Any change here must
# propagate to references/auto-approve.md (and SKILL.md if the contract
# shifts), and vice versa. Always returns 0 (soft-fail policy).
gh_pr_reply_auto_approve_step8() {
    local PR_NUMBER="$1" TARGET_REPO="$2" COMMENT_COUNT="$3" \
          PR_STATE="$4" PR_IS_DRAFT="$5" PR_REVIEW_DECISION="$6"

    # G2 (defensive): SKILL.md normally short-circuits at Step 2.5 before
    # reaching here, but a future refactor could land Step 8 in a path
    # where COMMENT_COUNT==0. Silently no-op in that case.
    if [ "${COMMENT_COUNT:-0}" -lt 1 ]; then
        return 0
    fi

    # G1a: env var must be set + non-empty.
    local _allow="${GH_PR_REPLY_AUTO_APPROVE_REPOS-}"
    if [ -z "$_allow" ]; then
        return 0
    fi

    # G1b: case-exact CSV membership (the helper convention — Status
    # names with internal spaces survive without padding around commas).
    case ",${_allow}," in
        *",${TARGET_REPO},"*) ;;
        *)
            printf '[gh-pr-reply] auto-approve: %s not in allowlist (GH_PR_REPLY_AUTO_APPROVE_REPOS=%s) — skip.\n' \
                "$TARGET_REPO" "$_allow" >&2
            return 0
            ;;
    esac

    # G3: PR must be OPEN and not a draft.
    if [ "$PR_STATE" != "OPEN" ]; then
        printf '[gh-pr-reply] auto-approve: PR #%s state=%s — skip (need OPEN).\n' \
            "$PR_NUMBER" "$PR_STATE" >&2
        return 0
    fi
    if [ "$PR_IS_DRAFT" = "true" ]; then
        printf '[gh-pr-reply] auto-approve: PR #%s is a draft — skip.\n' "$PR_NUMBER" >&2
        return 0
    fi

    # G4: reviewDecision must be empty/null or APPROVED.
    case "${PR_REVIEW_DECISION-}" in
        ""|null|APPROVED) ;;
        *)
            printf '[gh-pr-reply] auto-approve: PR #%s reviewDecision=%s — skip (need null|APPROVED).\n' \
                "$PR_NUMBER" "$PR_REVIEW_DECISION" >&2
            return 0
            ;;
    esac

    # All guards pass. Audit-trace + scoped bypass call.
    printf '[gh-pr-reply] auto-approve: solo-repo allowlist match → bypassing #393 fail-closed guard for PR #%s\n' \
        "$PR_NUMBER" >&2

    _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
        _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review"
    local _rc=$?
    if [ "$_rc" -ne 0 ]; then
        printf '[gh-pr-reply] auto-approve: helper rc=%s — continuing (soft-fail).\n' "$_rc" >&2
    fi

    # Sanity: the bypass binding must be scoped to the helper call only.
    # If a future refactor turned the prefix form into an export, this
    # would leak. The bats suite asserts the variable is unset post-call.
    return 0
}
