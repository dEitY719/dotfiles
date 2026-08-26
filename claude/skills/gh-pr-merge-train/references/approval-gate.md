# gh:pr-merge-train — Approval gate (D-5, F-7)

Read the repo's **actual** policy once, in Step 2, and obey it. This skill never
bypasses an approval requirement and never manufactures one that the platform
does not impose.

## Read the requirement

The rules that apply to the base branch, ruleset and branch-protection alike:

```bash
GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/rules/branches/$BASE" \
  --jq '[.[] | select(.type == "pull_request")
             | .parameters.required_approving_review_count] | max // empty'
```

`$BASE` is the PR's `baseRefName` (usually `main`). `max` because more than one
ruleset can apply and the strictest wins.

Three outcomes:

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

Read the requirement **once** per run — it is repo policy and does not change
mid-train. Apply it per PR against that PR's own `reviewDecision`:

- gate off (`0`, or no rule) → no approval check at all.
- gate on and `reviewDecision == APPROVED` → proceed.
- gate on and anything else (`REVIEW_REQUIRED`, `CHANGES_REQUIRED`, `""`) →
  `[SKIPPED] approval required (reviewDecision=<value>)`, next PR.

A `CHANGES_REQUESTED` PR is skipped **even when the gate is off**: someone
explicitly blocked it, and the absence of a platform rule does not overrule a
human's stated objection.
