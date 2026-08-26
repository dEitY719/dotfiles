# gh:pr-merge-train — Approval gate (D-5, F-7)

Read the repo's **actual** policy and obey it. This skill never bypasses an
approval requirement and never manufactures one that the platform does not
impose.

## Read the requirement — once per distinct base branch

Rulesets are frequently scoped to a branch pattern, so the answer is a property
of the **base branch**, not of the repo. Read it per distinct `baseRefName` in
the Step 2 queue and **cache it per base**: a single-base queue — the normal
case for `--author @me` — therefore costs exactly one call, and a mixed queue
costs one call per base rather than one per PR.

```bash
BASE_ENC=$(jq -rn --arg b "$BASE" '$b|@uri')
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/rules/branches/$BASE_ENC" \
  --jq '[.[] | select(.type == "pull_request")
             | .parameters.required_approving_review_count] | max // empty'
```

`$BASE` is the queue's `baseRefName`, which Step 2's `gh pr list --json`
already returned — never guess `main`, and never spend a `gh pr view` on it.
`max` because more than one ruleset can apply and the strictest wins.

**The percent-encoding is load-bearing**, not tidiness: an unencoded `/` in a
base like `release/2026.08` makes the path
`repos/O/R/rules/branches/release/2026.08`, which is a *different* endpoint —
the call fails, and the fail-closed default below then skips every PR in the
queue. `@uri` turns the slash into `%2F` so the ref stays one path segment.

Three outcomes, per base:

| Result | Meaning | Gate |
|---|---|---|
| `0` | a `pull_request` rule exists and asks for **zero** approvals | **skip the approval check** |
| `>= 1` | approvals are required | `reviewDecision` must be `APPROVED` |
| empty (no `pull_request` rule) | the platform imposes no PR review rule | skip the approval check |
| **call failed** | unknown | **fail-closed: treat as required** |

## Why skipping at `0` is not a bypass

`gh:pr-merge` refuses un-approved PRs and points at `gh:pr-merge-emergency`.
That is right for a human at a keyboard, but wrong as a train's normal path,
for two reasons that compound:

1. `gh:pr-approve` **cannot approve a self-authored PR** — GitHub forbids it.
   With `--author @me` (D-7), every PR in this train is self-authored. So the
   approval the gate wants can never be obtained by any skill in this repo.
2. `gh:pr-merge-emergency` would satisfy the gate, but it exists to create an
   audit trail for an *exception*: a reason comment plus a follow-up incident
   issue, every time. On the normal path it would file an incident issue per
   merge. Incidents that happen on schedule are not incidents.

When the ruleset says `required_approving_review_count = 0`, the platform is
stating that this repo does not require approval. Following that is **obeying
the policy, not routing around it** — the safety boundary is exactly where the
repo owner put it. On a repo that does require approvals, the same code path
refuses the merge and records the reason. Nothing is weakened.

## Why the gate being off is not sufficient

The gate above answers "does *the platform* require an approval". It does not
answer "will `gh:pr-merge` accept this PR", and those are not the same
question. `gh:pr-merge` Step 2 hard-stops on `reviewDecision != APPROVED` and
makes exactly one exception — base-branch protection **absent** *and*
`reviewDecision == ""` (`gh-pr-merge/references/strategy-selection.md` →
"Branch protection detection"). A **non-empty, non-`APPROVED`**
`reviewDecision` (`REVIEW_REQUIRED`, `CHANGES_REQUESTED`) stops it either way.

So a PR can pass this skill's gate and still be refused downstream. Left
alone, that PR burns all three F-5 attempts against a decision that cannot
change, lands as `[FAILED]`, and — since NF-2 forbids `gh:pr-merge-emergency`,
the only thing that would clear it — comes back `[FAILED]` on every subsequent
tick. **A train must never be able to produce an unclearable `[FAILED]`.**

Therefore: **check `reviewDecision` before calling `gh:pr-merge`, even when the
gate is off.** A non-empty value that is not `APPROVED` is
`[SKIPPED] gh:pr-merge refuses reviewDecision=<value>` — retriable the moment a
human approves or dismisses the review, and never an attempt.

The empty (`""`) case needs no rule of its own: with protection absent
`gh:pr-merge` accepts it by design, and with protection present a review
requirement is almost always configured too — so this gate is already on and
the PR is already `[SKIPPED] approval required`.

## Why lookup failure is fail-closed

A merge is hard to undo. A skipped PR is trivially retried on the next tick.
When the two error directions are that asymmetric, the cheap mistake is the one
to make: an unreadable ruleset is treated as "approval required", so unapproved
PRs are `[SKIPPED] ruleset unreadable — approval assumed required` and nothing
merges on a guess.

This is the opposite default from `gh:pr-merge`'s solo-repo accommodation
(protection absent → accept an empty `reviewDecision`). That accommodation is
sound for one deliberate, human-invoked merge; as an unattended loop's default
it would turn every transient API failure into a batch of unreviewed merges.

## Applying it per PR

Look up the requirement for **that PR's own base**, from the per-base cache
above — the read happens once per distinct base, not once per PR and not once
per run. Then apply it against that PR's own `reviewDecision`:

- gate on and `reviewDecision == APPROVED` → proceed.
- gate on and anything else (`REVIEW_REQUIRED`, `CHANGES_REQUESTED`, `""`) →
  `[SKIPPED] approval required (reviewDecision=<value>)`, next PR.
- gate off and `reviewDecision` non-empty and not `APPROVED` →
  `[SKIPPED] gh:pr-merge refuses reviewDecision=<value>`, next PR (previous
  section — this is the case that would otherwise become an unclearable
  `[FAILED]`).
- gate off and `reviewDecision` `APPROVED` or `""` → no approval check at all.

A `CHANGES_REQUESTED` PR is skipped **even when the gate is off**: someone
explicitly blocked it, and the absence of a platform rule does not overrule a
human's stated objection.
