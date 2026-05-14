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
- **Declined** — count of comments classified DECLINE.
- **Answered** — count of comments classified QUESTION.
- **Closing line** — `-> All comments replied to.` confirms the
  politeness contract was met.

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
