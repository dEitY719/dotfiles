# gh:pr-merge-train — Review verdict gate (#1564)

A PR does not enter `gh:pr-merge` unless a reviewer said so. This gate is the
consumer of two labels; it never forms an opinion of its own and never reads a
comment body.

Producer SSOT — how the labels are decided and written:
`devx-pr-review-all/references/review-verdict-label.md`.

## The decision table

Applied to every PR that survived Step 2's `_gh_pr_merge_train_filter_targets`.
Both labels come from the `labels` field that Step 2's `gh pr list --json` has
already returned — **this step makes no API call of its own.**

| Labels present | Queue verdict |
|---|---|
| `review-blocked` (regardless of `review-passed`) | `[SKIPPED] review-blocked — reviewer verdict is blocking` |
| neither label | `[SKIPPED] review not verified — no review-passed label` |
| `review-passed` only | stays in the queue |

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_merge_train.sh"

if printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_blocked_label; then
    echo "[SKIPPED] review-blocked — reviewer verdict is blocking"
elif ! printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_passed_label; then
    echo "[SKIPPED] review not verified — no review-passed label"
fi
```

`review-blocked` is tested **first**, so it wins over a stale `review-passed`
if both are somehow present. #1563's invalidation should make that
unreachable — every skill that advances a PR's head drops the stale verdict —
but a gate on a merge has to be deterministic about a state it does not
expect, not merely unlikely to meet it.

Neither outcome is an F-5 attempt, and neither is ever `[FAILED]`: a withheld
verdict is a working review, not a broken train (the same rule
`report-format.md` states for the delegated-review reasons).

## Why absence is blocking

"Not reviewed" and "reviewed and passed" are different states, and a gate that
collapses them is worse than no gate: it advertises a guarantee it does not
provide. #1527's reproduction is PR #1518 — two independent blocking verdicts
posted, merged 32 minutes later, 5 BLOCKERs into `main` (#1520, PR #1522) —
and the reason the verdicts never reached the merge decision is precisely that
nothing distinguished "no signal" from "green signal".

The cost of the strict direction is bounded and visible. A PR the gate skips
is one label away from moving: a re-review issues it, or a human adds it. The
cost of the permissive direction is an unreviewed merge, which is not
recoverable by any label.

**Expect a cliff at rollout.** Every PR open when this gate lands carries no
verdict label and is `[SKIPPED]` until it is reviewed. That is the design
working, not a regression.

## Why no time backstop

`reply-pending` has a staleness window
(`_gh_pr_merge_train_reply_pending_stale_minutes`, 90 min) because it is a
*hard skip that only its writer can lift*: a session that died mid-pass would
wedge its PR forever, so the label has to expire.

These labels have the opposite shape. Absence is already the blocking state,
so there is nothing for time to release — expiring `review-passed` would only
move a PR from "verified" to "not verified", which is where an un-reviewed PR
already sits. And expiring `review-blocked` would silently promote a blocked
PR to merely unverified, then to mergeable the moment any pass label appeared.
A window here would weaken the gate, not bound it.

Do not add one.

## What this gate is not

- **Not the board `Approved` gate.** `#1513` retired that, and this does not
  revive it. The signal here is a label written by the reviewer fan-out, not a
  project-board column.
- **Not the approval gate.** `approval-gate.md` answers "does the *platform*
  require an approval, and does `gh:pr-merge` accept this `reviewDecision`".
  This answers "did the reviewers pass it". A PR must clear both; they are
  independent questions and each has its own `[SKIPPED]` reason.
- **Not a comment parser.** The train never reads review comment bodies.
  Parsing lives entirely in the producer, and that direction is deliberate: a
  reviewer reformatting its verdict line yields `unknown` → no label → a
  skipped PR. Move the parsing here and the same reformat would silently
  *unlock* the gate.
- **Not part of `_gh_pr_merge_train_filter_targets`.** That filter drops its
  rejects silently before the queue exists, and `report-format.md` documents
  those PRs as never listed. #1564 requires a visible per-PR line, so this
  runs as a queue-level step over what the filter already passed.

## Provisioning

`_gh_pr_edit_safe_label` refuses to auto-create a missing label (#326), so
without provisioning the producer can never issue either one and every PR
skips forever. `gh:label-bootstrap` provisions both from the `pipeline|` feed
in `gh-label-bootstrap/references/gh-labels.md`, and `--prune` preserves them.

## Related

- `devx-pr-review-all/references/review-verdict-label.md` — producer SSOT
- `report-format.md` — where the two `[SKIPPED]` reasons are tabled
- `routing-table.md` — the F-3 per-PR re-check that closes the mid-run race
- `ordering.md` — the `reply-pending` label's lifecycle, the *timing* signal
  this *content* signal sits beside
