# Board Approval Gate — fail-closed pre-merge check

Step 2-B runs **before** Step 3 and gates the merge on the team's
projectV2 board column. See `board-policy.md` for the rule set and the
cross-link to `gh-pr-approve`.

```bash
# Reuse the SSOT query helper — never inline a fresh GraphQL block.
# helper-fallback NF-1 (#644): silent-skip when helper missing; never hard-fail.
# Defense-in-depth (#724): a sourced-but-undefined function would let
# `_gh_project_status_query_current` expand to nothing, BOARD_STATUS would
# be empty, and the empty-status branch would silently let merges through
# — bypassing the board approval gate. Detect that case explicitly.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    . "$_HELPER"

    if ! command -v _gh_project_status_query_current >/dev/null 2>&1; then
        printf '[gh-pr-merge] %s sourced but _gh_project_status_query_current undefined — board approval gate skipped (#724).\n' \
            "$_HELPER" >&2
    # Operator escape hatch: GH_PR_MERGE_SKIP_BOARD_CHECK=1
    # Use for in-transition repos or one-shot ops (also leaves an audit signal:
    # any reviewer can re-run gh-pr-merge without the env var to verify).
    elif [ "${GH_PR_MERGE_SKIP_BOARD_CHECK:-0}" != "1" ]; then
        BOARD_STATUS=$(GH_REPO="$TARGET_REPO" \
            _gh_project_status_query_current pr "$PR_NUMBER" 2>/dev/null || true)

        # Empty result = no projectV2 attached OR no read access.
        # Auto-skip in both cases — the merge gate is opt-in by board attachment.
        if [ -n "$BOARD_STATUS" ] && [ "$BOARD_STATUS" != "Approved" ]; then
            echo "Refusing to merge PR #$PR_NUMBER — board Status is \"$BOARD_STATUS\", required \"Approved\"."
            echo "  Have a teammate move the card to Approved, or use /gh-pr-merge-emergency for admin bypass."
            echo "  One-shot escape: GH_PR_MERGE_SKIP_BOARD_CHECK=1 /gh-pr-merge $PR_NUMBER"
            exit 2
        fi
    fi
fi
# helper missing → board approval gate is silently skipped (NF-1).
```

## Failure modes

- Board Status `!= Approved` (and non-empty) → exit 2, redirect to
  `/gh-pr-merge-emergency`.
- Empty Status (no projectV2 attached, or query failed) → silently
  continue. Repos without a board run on the legacy `reviewDecision`
  gate from Step 2 alone.
- `GH_PR_MERGE_SKIP_BOARD_CHECK=1` → skip Step 2-B entirely. Document
  the reason in the operator's commit message or Slack channel; this
  flag is for repos in transition, not a quiet-the-warning button.
