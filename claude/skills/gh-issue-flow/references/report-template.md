# gh:issue-flow — Step 3: Report

If all steps succeeded:

```
gh:issue-flow complete (#<N>)
  [OK] Step 1: gh:issue-implement       (<n files changed>, <n tests passed>)
  [OK] Step 2: gh:commit                (<sha> "<subject>")
  [OK] Step 3: gh:pr                    (PR #<M>)
  [OK] Step 4: devx:schedule            (pr-reply in 5 min, job: <id>)
  [OK] Step 5: gh:pr-resolve-conflict   (no conflicts / resolved)
  [OK] Step 6: ai-metrics               (~X tokens · ~M h · ~L min)
  PR URL: <pr-url>
```

If Step 2.6 soft-failed, show `[WARN] Step 6: ai-metrics  (skipped — <reason>)` instead.

If a step failed:

```
gh:issue-flow stopped at step <i>/5 (<skill-name>)
  [OK] Step 1: gh:issue-implement  (<summary>)
  [FAIL] Step <i>: <skill-name>       (<failure reason>)
  [SKIP] Steps <i+1>..5               (not reached)

Resume after fix:
  /<commands to finish>
```

Resume hint logic:
- Failed at step 1 → `/gh-issue-implement <N>` (user decides retry).
- Failed at step 2 → `/gh-commit && /gh-pr <N>`.
- Failed at step 3 → `/gh-pr <N>`.
- Failed at step 4 → `/devx:schedule --time 5 "/gh-pr-reply <PR_NUM>"`.
- Failed at step 5 → `/gh-pr-resolve-conflict <PR_NUM>`.
