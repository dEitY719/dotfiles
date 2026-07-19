# gh:issue-flow — Step 3: Report

If all steps succeeded:

```
gh:issue-flow complete (#<N>)
  [OK] Step 1: gh:issue-implement       (<n files changed>, <n tests passed>)
  [OK] Step 2: gh:commit                (<sha> "<subject>")
  [OK] Step 3: gh:pr                    (PR #<M>)
  [OK] Step 4: devx:pr-review-all       (agy+codex+simplify, reply in 8 min)
  [OK] Step 5: gh:pr-resolve-conflict   (no conflicts / resolved)
  [OK] Step 5.1: gh:pr-resolve-outdated (up to date / rebased)
  [OK] Step 6: ai-metrics               (~X tokens · ~M h · ~L min)
  PR URL: <pr-url>
```

Step 4 (`devx:pr-review-all`) is soft-fail — its row uses `[SKIP]`/`[WARN]`
for the gate's degraded cases (the delegated skill reports the per-lane
detail):
- `[SKIP] Step 4: devx:pr-review-all  (agy/codex absent)` — no CLI.
- `[SKIP] Step 4: devx:pr-review-all  (simplify: no change)` — clean tree, no commit.
- `[WARN] Step 4: devx:pr-review-all  (<reason>)` — review/simplify error, continued.

If Step 2.6 soft-failed, show `[WARN] Step 6: ai-metrics  (skipped — <reason>)` instead.

If a step failed:

```
gh:issue-flow stopped at step <i>/6 (<skill-name>)
  [OK] Step 1: gh:issue-implement  (<summary>)
  [FAIL] Step <i>: <skill-name>       (<failure reason>)
  [SKIP] Steps <i+1>..6               (not reached)

Resume after fix:
  /<commands to finish>
```

Resume hint logic:
- Failed at step 1 → `/gh-issue-implement <N>` (user decides retry).
- Failed at step 2 → `/gh-commit && /gh-pr <N>`.
- Failed at step 3 → `/gh-pr <N>`.
- Failed at step 4 → `/devx-pr-review-all <PR_NUM> <remote> --defer-reply 8`.
- Failed at step 5 → `/gh-pr-resolve-conflict <PR_NUM>`.
- Failed at step 5.1 → `/gh-pr-resolve-outdated <PR_NUM>`.

The quality gate now lives inside Step 4 (`devx:pr-review-all`), which is
soft-fail and never produces a `stopped at` report — it only contributes
`[OK]`/`[SKIP]`/`[WARN]` rows to the success template above.
