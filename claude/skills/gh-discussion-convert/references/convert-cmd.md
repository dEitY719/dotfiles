# gh:discussion-convert — Step 5-8 Convert Command

Detail companion to SKILL.md Steps 5 through 8. Reads the JSON
captured in Step 2 (the `_gh_discussion_fetch` output) and runs the
emulated convert sequence in order.

Inputs bound by the caller:

- `$TARGET_REPO`        — `owner/repo` from Step 1
- `$N`                  — Discussion number (positional arg)
- `$DISC_JSON`          — path to the temp file holding the JSON from
                          `_gh_discussion_fetch`
- `$OPT_NO_COMMENT`     — `1` if `--no-comment` was passed
- `$OPT_NO_LOCK`        — `1` if `--no-lock` was passed
- `$OPT_NO_CLOSE`       — `1` if `--no-close` was passed
- `$OPT_NO_BOARD_SYNC`  — `1` if `--no-board-sync` was passed

```bash
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/shell-common/functions/gh_project_status.sh"

DISC_ID=$(jq -r '.id'     "$DISC_JSON")
DTITLE=$(jq -r '.title'   "$DISC_JSON")
DCAT=$(jq -r '.category'  "$DISC_JSON")
DCLOSED=$(jq -r '.closed' "$DISC_JSON")
DLOCKED=$(jq -r '.locked' "$DISC_JSON")

# Step 3 — category guard (done by caller; this file assumes pass).

# Step 4 — idempotency check.
EXISTING=$(gh issue list --repo "$TARGET_REPO" --state all \
    --search "in:body \"Originated from discussion #${N}\"" \
    --json number,url --limit 1 --jq '.[0].url')
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
    printf '[OK] Discussion #%s already converted to %s\n' "$N" "$EXISTING"
    exit 0
fi

# Step 5 — create the issue with the backlink prepended.
ISSUE_BODY=$(mktemp) && trap 'rm -f "$ISSUE_BODY"' EXIT
printf 'Originated from discussion #%s\n\n' "$N" >"$ISSUE_BODY"
jq -r '.body' "$DISC_JSON" >>"$ISSUE_BODY"

ISSUE_URL=$(gh issue create --repo "$TARGET_REPO" \
    --title "$DTITLE" --body-file "$ISSUE_BODY")
ISSUE_NUMBER="${ISSUE_URL##*/}"

# Step 6 — board sync (best-effort).
if [ "${OPT_NO_BOARD_SYNC:-0}" != "1" ]; then
    _gh_project_status_sync issue "$ISSUE_NUMBER" "In progress" \
        --only-from "Backlog,Ready" || true
fi

# Step 7 — backlink comment on the discussion (best-effort).
if [ "${OPT_NO_COMMENT:-0}" != "1" ]; then
    CBODY=$(mktemp)
    printf 'Linked to issue #%s -- decision tracked there.\n' \
        "$ISSUE_NUMBER" >"$CBODY"
    _gh_discussion_comment "$DISC_ID" "$CBODY" >/dev/null \
        || printf '[WARN] discussion comment failed -- continuing\n' >&2
    rm -f "$CBODY"
fi

# Step 8 — close + lock (best-effort, conditional on current state).
if [ "${OPT_NO_CLOSE:-0}" != "1" ] && [ "$DCLOSED" != "true" ]; then
    _gh_discussion_close "$DISC_ID" RESOLVED >/dev/null \
        || printf '[WARN] discussion close failed -- continuing\n' >&2
fi
if [ "${OPT_NO_LOCK:-0}" != "1" ] && [ "$DLOCKED" != "true" ]; then
    _gh_discussion_lock "$DISC_ID" >/dev/null \
        || printf '[WARN] discussion lock failed -- continuing\n' >&2
fi

printf '[OK] Discussion #%s -> Issue #%s: %s\n' \
    "$N" "$ISSUE_NUMBER" "$ISSUE_URL"
```

확인 질문하지 말고 즉시 실행.

## Why four primitive mutations instead of one

`Convert to issue` lives only in the GitHub UI as of 2026-05. There
is no documented REST endpoint and the GraphQL schema does not expose
a `convertDiscussion` mutation. Until GitHub ships one, the
combination of `createIssue` + `addDiscussionComment` +
`closeDiscussion` + `lockLockable` reproduces every observable
side-effect of the native convert flow except the "transferred to
issue" UI banner. The lost banner is acceptable; the policy
invariants it visualises (close + bidirectional backlink + lock) are
still mechanically enforced here.

## Why `gh issue create` instead of GraphQL `createIssue`

The Issue mutation needs `repositoryId` (a node ID), default labels,
default assignee, and milestone handling — all of which `gh issue
create` resolves from `owner/repo` automatically and prints a stable
URL we can scrape for the issue number. A raw `createIssue` GraphQL
call would force this skill to re-implement that resolution chain,
duplicating logic that already lives in `gh:issue-create` /
`gh:issue-implement`.

## Why best-effort on Steps 6 / 7 / 8

The SSOT invariant is "decided Discussion -> tracked Issue with
backlink". Step 5 alone satisfies that contract. Steps 6 / 7 / 8 are
ergonomic helpers (board hygiene, reverse backlink, locked forum).
Rolling back the new Issue when one of them flakes would leave the
user in a worse state — Discussion still open, no Issue, work lost.
We warn and keep going.

## Idempotency mechanics

Step 4's `gh issue list --search "in:body ..."` relies on GitHub's
search indexer, which lags writes by a few seconds. The race window
where two near-simultaneous `gh:discussion-convert` invocations could
both miss the index and create duplicate Issues is real but tiny;
human review at the Issue list is the last defense. We do not block
the skill on a sleep-and-recheck because the realistic call pattern
is one human running the skill once.
