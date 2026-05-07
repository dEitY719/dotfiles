---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr
  → devx:schedule (pr-reply, 10 min) → gh:pr-resolve-conflict for a
  single issue number. Use when the user runs /gh:issue-flow,
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

## ⚠️ CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop after Step 2.1.** When `gh:issue-implement`
emits its `Next: /gh-commit && /gh-pr <N>` success hint, the model treats it
as a final answer and ends the turn — leaving the user to manually re-trigger
`gh:commit` and `gh:pr`. Reported by users as "100번 실행하면 50번은 stop"
(half of all runs stop early). See issue #333 for history.

**The mechanical guard is `--no-next-hint`** on the Step 2.1 invocation
(`gh:issue-implement` already supports the flag and suppresses its trailing
`Next:` line when set). With the trip-wire gone, the model sees a plain
success report and proceeds naturally to Step 2.2. **Do not drop this flag.**
If you edit Step 2 in any way, re-verify `--no-next-hint` is still present.

**Zero conversational text between the five `Skill()` calls in Step 2.**
No recap, no "now committing", no markdown headers, no progress bullets —
those tokens read as a turn-ending summary and re-introduce the early-stop.
The only text allowed in Step 2 is the final Step 3 report.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

The help output explicitly names the 5 chained skills:
gh:issue-implement, gh:commit, gh:pr, devx:schedule, gh:pr-resolve-conflict.

## Step 1: Parse Args

- `issue-number` — required, positive integer.
- `remote` — default `origin`.

This skill takes no `mode` arg; implementation is always `direct`.

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 2.6.

## Step 2: Chain the 5 Skills

Invoke in order. Each uses Claude Code's Skill tool. Each runs only
if the previous completed successfully.

1. **Step 2.1 — gh:issue-implement**
   ```
   Skill(gh:issue-implement, "<N> direct <remote> --no-next-hint")
   ```
   `--no-next-hint` is **load-bearing** — it suppresses the trailing
   `Next:` hint that would otherwise read as a turn-ending answer
   (see CRITICAL CONTRACT above). Track success = skill returned its
   success report (not failure). **Now invoke Step 2.2 — no recap,
   no summary, no header.**

2. **Step 2.2 — gh:commit** (only if 2.1 succeeded)
   ```
   Skill(gh:commit)
   ```
   gh:commit auto-detects the issue number from the conversation
   (the `#<N>` was just mentioned by Step 2.1's report), so no
   explicit args needed. **Now invoke Step 2.3 — no recap, no
   summary, no header.**

3. **Step 2.3 — gh:pr** (only if 2.2 succeeded)
   ```
   Skill(gh:pr, "<N>")
   ```
   Passing the issue number ensures `Closes #<N>` ends up in the PR
   body via gh:pr's Step 3 (issue resolution).
   After this step succeeds, extract `PR_NUM` from the PR URL in the
   output (last path segment of the `https://github.com/.../pull/<M>` URL).
   **Now invoke Step 2.4 — no recap, no summary, no header.**

4. **Step 2.4 — devx:schedule** (only if 2.3 succeeded)
   ```
   Skill(devx:schedule, "--time 10 \"/gh-pr-reply <PR_NUM>\"")
   ```
   Schedules `/gh-pr-reply <PR_NUM>` to run 10 minutes after PR creation,
   giving CI checks and reviewers time to post before the bot replies.
   **Now invoke Step 2.5 — no recap, no summary, no header.**

5. **Step 2.5 — gh:pr-resolve-conflict** (only if 2.4 succeeded)
   ```
   Skill(gh:pr-resolve-conflict, "<PR_NUM>")
   ```
   Checks and resolves any merge conflicts in the PR via rebase.
   If the PR is already conflict-free (`MERGEABLE == MERGEABLE`), the
   skill prints "PR은 이미 충돌 없음 — skip." and exits successfully —
   this is the expected case for a freshly created PR. **Now invoke
   Step 2.6 — no recap, no summary, no header.**

6. **Step 2.6 — Post AI Metrics to Issue** (only if 2.5 succeeded; soft-fail)

   Post a flow-level aggregate metrics comment on the **linked GitHub Issue**.
   The PR body already carries the per-step `<!-- ai-metrics:gh-pr -->` block
   written by `gh:pr`; this step adds the total across all five sub-skills to
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
| devx:schedule (pr-reply) | ~${SCHEDULE_MIN:-?} min |
| gh-pr-resolve-conflict | ~${CONFLICT_MIN:-?} min |
| **합계** | **~$ELAPSED min** |

👤 예상 사람 시간: ~$HUMAN_H h · 📊 ~$TOKENS tokens

<!-- ai-metrics:gh-issue-flow tokens=$TOKENS human_h=$HUMAN_H ai_min=$ELAPSED -->"
```

## Step 3: Report

If all steps succeeded:
```
gh:issue-flow complete (#<N>)
  ✓ Step 1: gh:issue-implement       (<n files changed>, <n tests passed>)
  ✓ Step 2: gh:commit                (<sha> "<subject>")
  ✓ Step 3: gh:pr                    (PR #<M>)
  ✓ Step 4: devx:schedule            (pr-reply in 10 min, job: <id>)
  ✓ Step 5: gh:pr-resolve-conflict   (no conflicts / resolved)
  ✓ Step 6: ai-metrics               (📊 ~X tokens · 👤 ~M h · 🤖 ~L min)
  PR URL: <pr-url>
```

If Step 2.6 soft-failed, show `⚠️ Step 6: ai-metrics  (skipped — <reason>)` instead.

If a step failed:
```
gh:issue-flow stopped at step <i>/5 (<skill-name>)
  ✓ Step 1: gh:issue-implement  (<summary>)
  ✗ Step <i>: <skill-name>       (<failure reason>)
  ⊘ Steps <i+1>..5               (not reached)

Resume after fix:
  /<commands to finish>
```

Resume hint logic:
- Failed at step 1 → `/gh-issue-implement <N>` (user decides retry).
- Failed at step 2 → `/gh-commit && /gh-pr <N>`.
- Failed at step 3 → `/gh-pr <N>`.
- Failed at step 4 → `/devx:schedule --time 10 "/gh-pr-reply <PR_NUM>"`.
- Failed at step 5 → `/gh-pr-resolve-conflict <PR_NUM>`.

## Constraints

- Never invoke implementation modes other than `direct`.
- Never retry a failed step. Human decides retry or fix.
- Never skip a step. All 5 or stop.
- Never mutate state between steps beyond what the sub-skills do.
  Exception: Step 2.6 may post a comment after Step 2.5 — this is
  intentional and must soft-fail (never block the flow). If a future
  variant of Step 2.6 needs to mutate PR labels or body, route through
  `_gh_pr_edit_safe_label` / `_gh_pr_edit_safe_body`
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
- **Never drop `--no-next-hint` from the Step 2.1 invocation.** It is
  the mechanical guard against the early-stop failure mode documented
  in the CRITICAL CONTRACT section. If a refactor of Step 2 looks
  cleaner without it, the refactor is wrong.
- **Zero conversational text between Skill() calls in Step 2.** No
  recap ("Step 2.1 complete, now committing..."), no progress
  markdown headers, no per-step bullet summaries. Such text reads as
  a turn-ending answer and re-introduces the early-stop. The only
  prose allowed inside Step 2 is the final Step 3 report.
- **Do NOT stop after any sub-skill completes.** Each step (2.1 through
  2.5) is a waypoint, not a final answer. Continue to the next step
  immediately. The only valid stopping points are: a step failure
  (output the failure report), or the Step 3 success report after all
  5 steps complete.
