#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_merge_board_gate.sh
# Source-of-truth mirror for the Step 4-B board approval gate snippet
# documented in claude/skills/gh-pr-merge/SKILL.md.
#
# The skill itself runs inside a Claude session, but the gating logic is
# a small bash block that can be tested in isolation: given the values
# of GH_PR_MERGE_SKIP_BOARD_CHECK and the current board Status, does the
# gate accept (rc=0), reject (rc=2), or skip (rc=0) the merge?
#
# Keep this file in sync with the gate block, which now lives in
# claude/skills/gh-pr-merge/references/board-approval-gate.sh.md (the
# SKILL.md Step points at it). If the skill block changes, mirror the
# change here so the bats suite catches drift.

# Stand-in for _gh_project_status_query_current. The real helper lives in
# shell-common/functions/gh_project_status.sh; tests inject mock values
# via FAKE_BOARD_STATUS so we don't need a live projectV2.
# FAKE_BOARD_STATUS_RC mirrors the helper's exit-code contract (#1354):
#   0 — query answered (value in stdout, or empty = no board attached)
#   1 — the query itself failed (auth / `project` scope / GraphQL error)
_gh_project_status_query_current() {
    printf '%s' "${FAKE_BOARD_STATUS-}"
    return "${FAKE_BOARD_STATUS_RC:-0}"
}

# Mirrors SKILL.md Step 4-B verbatim. Any change here must propagate to
# the SKILL.md block, and vice versa. Returns:
#   0 — proceed with merge (Approved, empty/no-board, or escape on)
#   2 — refuse merge (query failed, or board Status set to anything other
#       than Approved)
gh_pr_merge_board_gate() {
    local _pr="$1" _repo="$2"

    if [ "${GH_PR_MERGE_SKIP_BOARD_CHECK:-0}" = "1" ]; then
        return 0
    fi

    local _status _rc
    _status=$(GH_REPO="$_repo" \
        _gh_project_status_query_current pr "$_pr" 2>/dev/null)
    _rc=$?

    # rc != 0 = the query itself failed — the gate was never evaluated,
    # so fail closed instead of merging on an unverified signal (#1354).
    if [ "$_rc" -ne 0 ]; then
        printf '[gh-pr-merge] board status query failed — gate not evaluated.\n' >&2
        printf 'Refusing to merge PR #%s — could not verify board approval status (query failed).\n' "$_pr"
        printf "  Check gh token 'project' scope / GraphQL access, or use GH_PR_MERGE_SKIP_BOARD_CHECK=1 to bypass.\n"
        return 2
    fi

    if [ -n "$_status" ] && [ "$_status" != "Approved" ]; then
        printf 'Refusing to merge PR #%s — board Status is "%s", required "Approved".\n' \
            "$_pr" "$_status"
        printf '  Have a teammate move the card to Approved, or use /gh-pr-merge-emergency for admin bypass.\n'
        printf '  One-shot escape: GH_PR_MERGE_SKIP_BOARD_CHECK=1 /gh-pr-merge %s\n' "$_pr"
        return 2
    fi

    # Empty status + rc 0 = no projectV2 attached — legitimate skip, the
    # merge gate is opt-in by board attachment.
    return 0
}
