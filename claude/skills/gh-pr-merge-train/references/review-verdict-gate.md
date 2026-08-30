# gh:pr-merge-train — Review verdict gate (#1564)

A PR does not enter `gh:pr-merge` unless a reviewer said so. This gate is the
consumer of two labels; it never forms an opinion of its own and never reads a
comment body.

Producer SSOT — how the labels are decided and written:
`devx-pr-review-all/references/review-verdict-label.md`.

## The decision table

Applied to every PR that survived Step 2's `_gh_pr_merge_train_filter_targets`.
Both labels come from the `labels` field that Step 2's `gh pr list --json` has
already returned — the label check itself makes no API call of its own. The
freshness check below (#1601) is the one exception: it costs one
`gh api --paginate` call, but only for a PR that already carries
`review-passed` alone (the case that would otherwise proceed unverified).

| Labels present | Queue verdict |
|---|---|
| `review-blocked` (regardless of `review-passed`) | `[SKIPPED] review-blocked — reviewer verdict is blocking` |
| neither label | `[SKIPPED] review not verified — no review-passed label` |
| `review-passed` only, marker sha matches current head | stays in the queue |
| `review-passed` only, marker sha stale or missing (#1601) | `[SKIPPED] review-passed label stale — head advanced without invalidation` |

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_merge_train.sh"
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"

if printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_blocked_label; then
    echo "[SKIPPED] review-blocked — reviewer verdict is blocking"
elif ! printf '%s' "$PR_JSON" | _gh_pr_merge_train_has_review_passed_label; then
    echo "[SKIPPED] review not verified — no review-passed label"
elif _gh_pr_merge_train_review_passed_stale "$N" "$TARGET_REPO" "$TARGET_HOST" "$HEAD_OID"; then
    echo "[SKIPPED] review-passed label stale — head advanced without invalidation"
    # Self-heal: the reader just proved what the writers missed, so drop the
    # stale label here too. Best-effort — a failed drop still leaves this
    # tick's [SKIPPED] correct; it only means the next tick pays for the same
    # sha check again.
    _gh_pr_drop_label "$N" review-passed "$TARGET_REPO" "$TARGET_HOST" >/dev/null 2>&1 || :
fi
```

This full form — including the `HEAD_OID` freshness branch — is what Step 4's
F-3 re-check runs (`routing-table.md`), right before a specific PR is acted
on. `SKILL.md` Step 3.5's queue-build pass runs only the first two branches
(the label-only prefix) over the whole Step-2 queue, on purpose: it has
neither `$HEAD_OID` nor the budget to pay one `gh api` call per queued PR when
most of them won't be reached this tick anyway. A `review-passed` PR that
passes Step 3.5 is provisionally queued; F-3 is what actually proves the
label is still trustworthy.

`review-blocked` is tested **first**, so it wins over a stale `review-passed`
if both are somehow present. #1563's invalidation should make that
unreachable — every skill that advances a PR's head drops the stale verdict —
but a gate on a merge has to be deterministic about a state it does not
expect, not merely unlikely to meet it.

## Freshness check (#1601)

The label-presence check above answers "was this PR ever verified"; it
cannot answer "was *this* head verified", because a label carries no data of
its own. #1563 tried to keep the two in sync by having every head-advancing
skill drop the label on push — but that list can never be complete: a manual
`git push --force-with-lease` from a human's shell, a GitHub web-UI commit, or
a future tool all advance the head with no hook this repo controls. Any of
those leaves a stale `review-passed` that the presence-only check above would
happily trust.

`_gh_pr_merge_train_review_passed_stale` (`shell-common/functions/gh_pr_merge_train.sh`)
closes that gap by verifying instead of trusting: it reads the last
`<!-- review-verdict:review-passed:<sha> -->` marker
`devx_pr_review_all_apply_label` posted when it applied the label
(`devx-pr-review-all/references/review-verdict-label.md` → "Freshness marker
for `review-passed`") and compares that sha against `$HEAD_OID` — the current
`headRefOid`, already added to F-3's `$STATE` fetch (`routing-table.md`). No
marker, or a marker whose sha does not match, is STALE — fail-closed, the
same direction `approval-gate.md` takes for an unreadable policy: an
undetermined answer costs one skip, and a skip is trivially retried.

This still does not make the train a comment parser in the sense "What this
gate is not" forbids below: it never reads a *reviewer's* verdict line, only
a fixed machine stamp this same subsystem writes for exactly this check.

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
- **Not a comment parser.** The train never reads *review* comment bodies —
  a reviewer's LGTM/BLOCKING prose. Parsing that lives entirely in the
  producer, and that direction is deliberate: a reviewer reformatting its
  verdict line yields `unknown` → no label → a skipped PR. Move the parsing
  here and the same reformat would silently *unlock* the gate. The #1601
  freshness check above reads a comment too, but a fixed machine-only marker
  the producer stamps for exactly this purpose, never a reviewer's own
  output — see "Freshness check" for why that line is not the one this rule
  guards.
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
