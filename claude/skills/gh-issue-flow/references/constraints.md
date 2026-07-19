# gh:issue-flow — Constraints

- Never invoke implementation modes other than `direct`.
- Never retry a failed step. Human decides retry or fix.
- Never skip a step. All 6 or stop.
- **Quality-gate soft-fail exception.** Step 2.4 (`devx:pr-review-all`)
  is additive polish, not gating: agy/codex absent → that lane skips
  (not a failure); `/simplify` produced no change → no commit; any error
  in review/simplify/commit → `[WARN]` and continue. The gate never stops
  the flow.
- **Simplify commit before rebase.** Step 2.4 commits + pushes any
  simplify changes **synchronously inside `devx:pr-review-all`** before it
  returns, so the tree is clean before the rebase steps 2.5 / 2.5.1 — a
  dirty working tree breaks `git rebase`.
- Step 2.5.1 (gh:pr-resolve-outdated) does a clean rebase-sync when the
  base moved forward with no conflicts; it is a no-op when the PR is
  already up to date.
- Never mutate state between steps beyond what the sub-skills do.
  Exception: Step 2.6 may post a comment after Step 2.5.1 — this is
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
  in `references/critical-contract.md`. If a refactor of Step 2 looks
  cleaner without it, the refactor is wrong.
- **Zero conversational text between Skill() calls in Step 2.** No
  recap ("Step 2.1 complete, now committing..."), no progress
  markdown headers, no per-step bullet summaries. Such text reads as
  a turn-ending answer and re-introduces the early-stop. The only
  prose allowed inside Step 2 is the final Step 3 report. The quality
  gate now runs inside the delegated Step 2.4 (`devx:pr-review-all`),
  so Step 2 is a clean six-`Skill()` sequence with no inline gate
  dispatch or Bash commit+push between calls.
- **Do NOT stop after any sub-skill completes.** Each step (2.1 through
  2.5.1, including the Step 2.4 quality gate) is a waypoint, not a final
  answer. Continue to the next step immediately. The only valid stopping
  points are: a step failure (output the failure report), or the Step 3
  success report after all 6 steps complete.
