---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr
  for a single issue number. Use when the user runs /gh:issue-flow,
  /gh-issue-flow, or asks "issue #16 처음부터 PR까지 자동으로",
  "이슈 구현하고 커밋하고 PR까지 한방에", "full flow on #42". Uses
  direct implementation mode only — for plan/brainstorming modes, use
  the atomic gh:issue-implement skill manually. Stops on first step
  failure with a resume-instructions report. Precondition: already on
  a feature branch in a dedicated worktree. Accepts
  `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
---

# gh:issue-flow — Issue → PR composition

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

The help output explicitly names the 3 chained skills:
gh:issue-implement, gh:commit, gh:pr.

## Step 1: Parse Args

- `issue-number` — required, positive integer.
- `remote` — default `origin`.

This skill takes no `mode` arg; implementation is always `direct`.

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 2.4.

## Step 2: Chain the 3 Skills

Invoke in order. Each uses Claude Code's Skill tool. Each runs only
if the previous completed successfully.

1. **Step 2.1 — gh:issue-implement**
   ```
   Skill(gh:issue-implement, "<N> direct <remote>")
   ```
   Track success = skill returned its success report (not failure).

2. **Step 2.2 — gh:commit** (only if 2.1 succeeded)
   ```
   Skill(gh:commit)
   ```
   gh:commit auto-detects the issue number from the conversation
   (the `#<N>` was just mentioned by Step 2.1's report), so no
   explicit args needed.

3. **Step 2.3 — gh:pr** (only if 2.2 succeeded)
   ```
   Skill(gh:pr, "<N>")
   ```
   Passing the issue number ensures `Closes #<N>` ends up in the PR
   body via gh:pr's Step 3 (issue resolution).

4. **Step 2.4 — Post AI Metrics to Issue** (only if 2.3 succeeded; soft-fail)

   Post a flow-level aggregate metrics comment on the **linked GitHub Issue**.
   The PR body already carries the per-step `<!-- ai-metrics:gh-pr -->` block
   written by `gh:pr`; this step adds the total across all three sub-skills to
   the Issue so the Issue thread is the single place to review full AI effort.
   This step soft-fails — warn on any error but never block the flow.

   a. Compute: `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`
   b. Issue type: parse the conventional-commit prefix from the issue title
      fetched in Step 2.1 (e.g. `feat`, `fix`, `refactor`).
   c. Human time: look up the issue type in `gh-issue-create`'s
      `references/metrics-baseline.md` (in the same skills directory).
      For `feat`, infer size from the implementation scope.
   d. Token estimate: character count of (issue body + implementation file reads) ÷ 4,
      rounded to nearest 500. Minimum 1 000.
   e. Post the aggregate comment on the linked issue (body template below).
   f. On failure: print `⚠️  ai-metrics comment failed (<reason>) — continuing.`

```bash
gh api "repos/$TARGET_REPO/issues/$ISSUE_NUMBER/comments" \
  -X POST \
  -f body="### ✅ gh-issue-flow 완료

| 단계 | AI 소요 |
|------|---------|
| gh-issue-implement | ~${IMPL_MIN:-?} min |
| gh-commit | ~${COMMIT_MIN:-?} min |
| gh-pr | ~${PR_MIN:-?} min |
| **합계** | **~$ELAPSED min** |

👤 예상 사람 시간: ~$HUMAN_H h · 📊 ~$TOKENS tokens

<!-- ai-metrics:gh-issue-flow tokens=$TOKENS human_h=$HUMAN_H ai_min=$ELAPSED -->"
```

## Step 3: Report

If all steps succeeded:
```
gh:issue-flow complete (#<N>)
  ✓ Step 1: gh:issue-implement  (<n files changed>, <n tests passed>)
  ✓ Step 2: gh:commit            (<sha> "<subject>")
  ✓ Step 3: gh:pr                (PR #<M>)
  ✓ Step 4: ai-metrics           (📊 ~X tokens · 👤 ~M h · 🤖 ~L min)
  PR URL: <pr-url>
```

If Step 2.4 soft-failed, show `⚠️ Step 4: ai-metrics  (skipped — <reason>)` instead.

If a step failed:
```
gh:issue-flow stopped at step <i>/3 (<skill-name>)
  ✓ Step 1: gh:issue-implement  (<summary>)
  ✗ Step <i>: <skill-name>       (<failure reason>)
  ⊘ Steps <i+1>..3               (not reached)

Resume after fix:
  /<commands to finish>
```

Resume hint logic:
- Failed at step 1 → `/gh-issue-implement <N>` (user decides retry).
- Failed at step 2 → `/gh-commit && /gh-pr <N>`.
- Failed at step 3 → `/gh-pr <N>`.

## Constraints

- Never invoke implementation modes other than `direct`.
- Never retry a failed step. Human decides retry or fix.
- Never skip a step. All 3 or stop.
- Never mutate state between steps beyond what the sub-skills do.
  Exception: Step 2.4 may edit the PR body after Step 2.3 — this is
  intentional and must soft-fail (never block the flow). If a future
  variant of Step 2.4 needs to mutate PR labels or body, route through
  `_pr_edit_safe_label` / `_pr_edit_safe_body`
  (`shell-common/functions/gh_pr_edit_safe.sh`); plain `gh pr edit
  --add-label` / `--body-file` silently exits 1 on repos with classic
  Projects attached (issue #326 Bug B).
- Do NOT preface or summarize beyond the compact report.
- Do NOT end the turn until the Step 3 report is issued (success or
  failure template). A `Next:` / resume-hint from a sub-skill
  (notably gh:issue-implement's `Next: /gh-commit && /gh-pr <N>`) is
  a waypoint during this composition, not a final answer — keep
  going. Don't let a success hint from 2.1 or 2.2 end the flow
  before Step 3.
