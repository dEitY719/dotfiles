# Final Summary — output table printed by `gh:pr-reply` Step 7

Print a table the user can scan after all replies are posted:

```
PR #123 review comments processed: 5 total
  Accepted: 3 (commits abc1234, def5678)
  Declined: 1
  Answered: 1
  [OK]   Step 8: auto-approve fired (helper rc=0)
  -> All comments replied to.
```

## Required fields

- **Total** — count of comments identified in Step 2 (after dedup).
- **Accepted** — count + the commit short-SHAs that landed the fixes.
- **Declined** — count of comments classified DECLINE.
- **Answered** — count of comments classified QUESTION.
- **Step 8 outcome row** — always present, rendered from the
  `STEP8_OUTCOME` variable bound by the auto-approve gate (see
  `references/auto-approve.md`). Missing this row means the gate
  never ran and the report is **incomplete** — that is the exact
  failure mode that issue #662 fixed (PR #659 on 2026-05-16 had
  Step 8 silently skipped by an executor assumption; the user only
  noticed because the board card stayed at `In review`).
- **Closing line** — `-> All comments replied to.` confirms the
  politeness contract was met.

## Step 8 outcome row template

The auto-approve gate (`Step 8`) always runs and always binds
`STEP8_OUTCOME` (`OK:fired` / `SKIP:<reason>` / `WARN:rc=<N>`). Map
the value to the row:

| `STEP8_OUTCOME` | Rendered row |
|---|---|
| `OK:fired` | `[OK]   Step 8: auto-approve fired (helper rc=0)` |
| `SKIP:allowlist_miss` | `[SKIP] Step 8: allowlist miss` |
| `SKIP:comment_count=0` | `[SKIP] Step 8: comment_count=0` |
| `SKIP:state=<X>` | `[SKIP] Step 8: state=<X>` |
| `SKIP:draft` | `[SKIP] Step 8: draft` |
| `SKIP:reviewDecision=<X>` | `[SKIP] Step 8: reviewDecision=<X>` |
| `WARN:rc=<N>` | `[WARN] Step 8: helper rc=<N> — continuing` |
| _unset_ | **Regression** — render the row as `[FAIL] Step 8: gate never evaluated (STEP8_OUTCOME unset — see issue #662)` and treat the report as incomplete |

### Contract

The Step 8 row MUST appear in every Step 7 report. A missing row is
not a stylistic omission — it means the executor skipped the gate
evaluation entirely (the issue #662 failure mode). bats regression
`tests/bats/skills/gh_pr_reply_auto_approve.bats` enforces the
underlying variable-binding contract; the Step 7 renderer enforces
the user-visible row.

## Optional appendix

If any comments were skipped as "already replied", list them at the
bottom under a `Skipped (already replied):` header with the comment IDs
or short bodies, so the user can verify nothing was silently ignored.

## Lingering `CHANGES_REQUESTED` nudge

Replying to comments and pushing fixes does NOT clear the PR's
`reviewDecision` — GitHub only flips that flag when the reviewer
explicitly re-reviews. After printing the table above, query the PR
state once more and emit a one-line nudge if the decision is still
`CHANGES_REQUESTED`. Without this, the user can mistake "all comments
replied to" for "PR ready to merge".

```bash
REVIEW_DECISION=$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json reviewDecision -q .reviewDecision 2>/dev/null)

if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  printf '\n  -> PR is still CHANGES_REQUESTED — reviewer must re-review.\n'
  printf '     Optional: gh pr review %s --request <reviewer>\n' "$PR_NUMBER"
fi
```

Soft-fail: if the `gh pr view` call errors (network blip, missing
scope), skip the nudge silently — the main summary already printed.
This check is independent of Step 8 (Solo-Repo Auto-Approve), whose
G4 guard explicitly refuses to auto-approve when `reviewDecision ==
CHANGES_REQUESTED`. Validated on PR
`dev-team-404/AgentToolbox#655` — the lingering CR state was the
exact gap that the run surfaced.
