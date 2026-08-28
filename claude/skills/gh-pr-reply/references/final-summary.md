# Final Summary — output table printed by `gh:pr-reply` Step 7

Print a table the user can scan after all replies are posted:

```
PR #123 review comments processed: 5 total
  Accepted: 3 (commits abc1234, def5678)
  Declined: 1
  Answered: 1
  -> All comments replied to.
```

## Required fields

- **Total** — count of comments identified in Step 2 (after dedup).
- **Accepted** — count + the commit short-SHAs that landed the fixes.
  ACCEPT + ACCEPT-PARTIAL; held in `ACCEPTED_COUNT`.
- **Declined** — count of comments classified DECLINE; held in
  `DECLINED_COUNT`.
- **Answered** — count of comments classified QUESTION.
- **Closing line** — `-> All comments replied to.` confirms the
  politeness contract was met.
- Step 6 reads `ACCEPTED_COUNT` / `DECLINED_COUNT` too, to decide whether
  `review-blocked` may be dropped (`references/verdict-label-removal.sh.md`).
  Both steps use the same counters — never re-derive them.
- **No board-promotion row** — `Approved` is owned by `gh:pr-approve`
  (#1350). This skill's only board write is the Step 6 `In review`
  recovery, which the table does not report.

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
REVIEW_DECISION=$(GH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json reviewDecision -q .reviewDecision 2>/dev/null)

if [ "$REVIEW_DECISION" = "CHANGES_REQUESTED" ]; then
  printf '\n  -> PR is still CHANGES_REQUESTED — reviewer must re-review.\n'
  printf '     Optional: gh pr review %s --request <reviewer>\n' "$PR_NUMBER"
fi
```

Soft-fail: if the `gh pr view` call errors (network blip, missing
scope), skip the nudge silently — the main summary already printed.
Validated on PR `dev-team-404/AgentToolbox#655` — the lingering CR
state was the exact gap that the run surfaced.
