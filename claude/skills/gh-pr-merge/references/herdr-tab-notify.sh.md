# herdr Tab Notify — post-merge idle-tab hint (soft-fail, read-only)

Runs inside Step 4 (post-merge housekeeping), after the board
reconciliations. `HEAD_REF` is the merged PR's `headRefName`, already
fetched by Step 2's `gh pr view --json ...,headRefName,...` — carry that
value forward, do **not** re-fetch it. Step 3's `--delete-branch` removes
the *remote* branch; the local branch a worktree is checked out on is
untouched, so the `git worktree list` lookup below still resolves.

Purpose: when the merged branch was implemented in a local git worktree
that still has a `herdr` agent tab parked on it, and that tab is `idle`,
print **one** informational line so the human can tear it down. Nothing is
closed, removed, or otherwise mutated — every herdr/git call here is a
read-only `list` (NF-2). A `working`/`blocked` agent prints nothing at
all: silence, not a second info line (F-4).

```bash
# F-1: locate the local worktree checked out on the merged branch.
# substr() rather than $2 so a worktree path containing spaces still
# resolves; --porcelain guarantees the "worktree <path>" / "branch <ref>"
# line pairing this relies on.
BRANCH="${HEAD_REF}"
WT_PATH=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/${BRANCH}" \
    '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' | head -1)

# NF-1: every gate below is a silent skip. No worktree (the merge ran on a
# different machine), no herdr, no jq → the merge report is unaffected.
if [ -n "$WT_PATH" ] && command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # F-2: read-only agent enumeration; match on cwd == worktree path.
    if AGENT_JSON=$(herdr agent list 2>/dev/null); then
        # head -1: two agents on one cwd is abnormal — take the first,
        # ignore the rest, warn about nothing (Error Cases).
        MATCH=$(printf '%s' "$AGENT_JSON" | jq -r --arg cwd "$WT_PATH" \
            '.result.agents[]? | select(.cwd == $cwd)
             | "\(.tab_id)\t\(.agent_status)\t\(.workspace_id)"' 2>/dev/null | head -1)

        if [ -n "$MATCH" ]; then
            TAB_ID=$(printf '%s' "$MATCH" | cut -f1)
            AGENT_STATUS=$(printf '%s' "$MATCH" | cut -f2)
            WS_ID=$(printf '%s' "$MATCH" | cut -f3)

            # F-4: working/blocked/anything-but-idle prints nothing at all,
            # and does not even pay for the second lookup.
            if [ "$AGENT_STATUS" = "idle" ]; then
                # Label is cosmetic — fall back to the raw workspace id when
                # this read-only lookup fails or the workspace is unlabeled.
                WS_LABEL=$(herdr workspace list 2>/dev/null | jq -r --arg id "$WS_ID" \
                    '.result.workspaces[]? | select(.workspace_id == $id) | .label' 2>/dev/null | head -1)

                # F-3: exactly one line, only for an idle agent.
                printf "[INFO] herdr tab %s/%s is idle for the merged branch's worktree (%s) — consider: herdr tab close %s / ai-worktree:teardown\n" \
                    "${WS_LABEL:-$WS_ID}" "$TAB_ID" "$WT_PATH" "$TAB_ID"
            fi
        fi
    fi
fi
```

## Failure modes

Every one of these is a silent skip that leaves the Step 5 merge report
byte-identical (NF-1). None of them warn, and none of them return
non-zero to the caller.

- **`HEAD_REF` empty / no local worktree on that branch** — the usual case
  when the PR was implemented on another machine, or the worktree was
  already torn down. `WT_PATH` is empty → nothing printed.
- **`herdr` not installed** — `command -v herdr` fails → nothing printed,
  and the rest of `gh:pr-merge` runs normally. This is the expected state
  on any machine without the agent runner.
- **`jq` not installed** — same silent skip; the agent JSON cannot be
  parsed, and a hint is not worth a hand-rolled parser.
- **`herdr agent list` fails** (daemon down, no local herdr server, non-zero
  exit) — the `if AGENT_JSON=...` guard swallows it → nothing printed.
- **No agent whose `cwd` equals the worktree path** — the worktree exists
  but no tab is parked on it → `MATCH` empty → nothing printed.
- **Agent found but `agent_status != "idle"`** (`working`, `blocked`, any
  future value) — nothing printed (F-4). Suggesting cleanup for a tab that
  is mid-run would be wrong, and a "still working" line would be noise.
- **Two or more agents on the same `cwd`** — abnormal; `head -1` takes the
  first, the rest are ignored, and no warning is emitted.
- **`herdr workspace list` fails, or the workspace has no label** —
  `WS_LABEL` is empty and `${WS_LABEL:-$WS_ID}` prints the raw workspace id.
  The hint still goes out; only its cosmetic prefix degrades.

## Read-only contract (NF-2)

This substep calls `git worktree list`, `herdr agent list`, and
`herdr workspace list` — enumerations only. It never closes a tab, never
deletes a worktree, and never writes to the herdr server. The suggested
cleanup commands are printed for a human to decide on and run.

`tests/bats/skills/gh_pr_merge_herdr_notify.bats` enforces this
mechanically: it greps this file and its fixture mirror for the literal
invocation substrings and fails if either appears.

## Mirror

`tests/bats/skills/_fixtures/gh_pr_merge_herdr_notify.sh` mirrors the bash
block above as the function `gh_pr_merge_herdr_notify "$HEAD_REF"`. If the
block here changes, mirror the change there so the bats suite catches drift.
