# gh:pr-merge-train — Review verdict gate (issue #1527)

The train's hard gate on whether **review** passed, as opposed to whether CI
passed. Producer and SSOT for the labels:
`devx-pr-review-all/references/review-verdict-label.md`.

## Why this gate exists

Before #1527 the train's real merge condition was:

```
CI green + not draft + not CONFLICTING + quiet period 11m
```

Nothing in it expressed "a reviewer approved". All three layers that could have
were empty at once — the repo ruleset asks for `required_approving_review_count=0`,
the board `Approved` gate was retired in #1513 (it permanently blocked
self-authored PRs), and `gh:pr-approve` cannot approve a self-authored PR at all.
`devx:pr-review-all` did produce verdicts, but only as prose inside a PR comment.

Result, measured on PR #1518: two independent lanes posted `판정: 블로킹`, and the
PR merged 32 minutes later with 5 BLOCKERs, needing a tracking issue (#1520) and a
follow-up PR (#1522) to undo. Defects CI cannot see — a rebase onto the wrong
branch, a hardcoded remote, unvalidated input reaching a skip-permissions prompt,
prefix matching with no path boundary — passed the entire pipeline unchallenged.

## The gate

Applied in **Step 2, at queue construction** — before ordering, before the
approval-gate lookup, before any remediation is attempted. `gh pr list` must
therefore request `labels` in its `--json` field set.

| labels on the PR | queue decision |
|---|---|
| `review-blocked` present | `[SKIPPED] review-blocked — reviewer verdict is blocking` |
| neither label | `[SKIPPED] review not verified — no review-passed label` |
| `review-passed` present (and not `review-blocked`) | stays in the queue |

`review-blocked` wins when both are somehow present: a stale `review-passed` that
a later blocking review failed to clear must not outrank the block.

**Absence is a skip, not a pass.** A PR nobody reviewed and a PR that passed
review are different states, and treating them alike is exactly the hole this
gate closes. This is also what makes the gate free of a time backstop (contrast
#1524's `reply-pending`): nothing merges on a timer, so nothing needs one.

## Why it is a `[SKIPPED]` and costs no attempt

Same shape as the `reviewDecision` pre-check in `train-loop.md` → "Gates
`gh:pr-merge` owns": the condition is deterministic, so delegating to a
remediation atom would burn all three F-5 attempts to arrive at a `[FAILED]` the
train has no way to clear. It is recorded up front, without delegating, and the
next tick re-evaluates it from scratch.

It is retriable by design, and cheaply:

- `gh:pr-reply` removes `review-blocked` once it has actually pushed fixes for
  the blockers, and re-review re-labels the PR.
- A human can add `review-passed` or remove `review-blocked` with one click at
  any time. That is the escape hatch, and it is deliberately manual.

## What this gate does NOT do

- **It never parses comment bodies.** The verdict is read once, by the producer,
  at labelling time (`devx:pr-review-all` Step 5). If the train grepped comments
  instead, a reviewer reformatting its verdict line would silently *unlock* the
  gate; with the label, the same reformat yields no label and a skipped PR.
- **It does not replace the approval gate.** `approval-gate.md` reads the repo's
  rulesets and classic branch protection — platform policy. This gate reads the
  pipeline's own review result. Both apply; either can skip a PR.
- **It does not replace the gate-off delegated review** (#1519 D-3,
  `train-loop.md` → "Delegated review on the gate-off path"). That runs later,
  per PR, and asks `gh:pr-approve` for a fresh judgement when the platform
  imposes no rule. This gate runs earlier, at queue construction, and only
  *reads* a verdict `devx:pr-review-all` already reached. They compose: a PR
  this gate drops never reaches the delegated review at all, which is the cheap
  ordering — a blocking verdict is already known, so paying for a second
  opinion to rediscover it would be waste.
- **It does not resurrect the board `Approved` gate** (#1513). The signal is the
  review *execution result*, not a human's board move — which is the distinction
  that keeps self-authored PRs from being permanently stuck.
- **It changes nothing for a manual single `gh:pr-merge`.** That skill does not
  read these labels; a deliberate human merge is unaffected.
