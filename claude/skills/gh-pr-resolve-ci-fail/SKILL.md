---
name: gh:pr-resolve-ci-fail
description: >-
  Fix a GitHub PR's red CI: read failing check logs, fix the cause locally.
  Use for /gh:pr-resolve-ci-fail, /gh-pr-resolve-ci-fail, "PR CI fail 해결",
  "CI fail 라벨 떼줘". Not a rebase conflict (gh:pr-resolve-conflict) or base
  sync (gh:pr-resolve-outdated).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "CI log analysis + root-cause identification + targeted fix; pattern-matching reasoning, no deep architectural decisions"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-resolve-ci-fail — CI Failure Resolution

## Help

Arg #1 `-h`/`--help`/`help` → read `references/help.md` verbatim, stop. No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for Step 7.

Positional: `[pr-number] [remote]`. Flags: `--wait <seconds>` (opt-in, default
off), `--label-variant <input>` (override canonical label).

- `remote` default `origin`. Missing → `git remote -v` and stop. Bind `TARGET_HOST` +
  `TARGET_REPO` from that one remote URL **before any `gh` call** per `references/github-target.md` (#1403).
- `pr-number` omitted → auto-detect via `GH_HOST="$TARGET_HOST" gh pr view --json
  number,state,headRefName` — no `--repo`, `gh` rejects it without a PR argument
  (`references/github-target.md` → "Exception"). No PR → stop. `--label-variant`
  normalized via `references/label-normalization.md`; unknown → fail-fast.

State `OPEN` required. Hard preconditions (refuses the repo default branch ·
clean tree · no in-progress rebase) in `references/safety.md` →
"Preconditions". Capture `BACKUP_SHA=$(git rev-parse HEAD)` for recovery.

## Step 2: Fetch Failing Checks

Pre-check — main 의 동일 workflow 가 inherited red 인지 먼저 확인한다.
Commands, judgment criteria, and transient-red exceptions: `references/ci-log-analysis.md` → "Pre-check (is main red?)".

### Failing-check fetch

`GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required --json
name,state,workflow,link`, filter `state == FAILURE`. All green → `[OK] no failing checks — nothing to resolve.` and stop.
Filter rubric + in-progress carveout: `references/ci-log-analysis.md` → "Step 2 — Fetch failing checks".

## Step 3: Fetch + Analyze Logs

Resolve each failing workflow's latest `RUN_ID`, dump `GH_HOST="$TARGET_HOST" gh
run view <id> --repo "$TARGET_REPO" --log-failed`, identify the root cause. Parsing rubric + common patterns (lint /
type / test / build): `references/ci-log-analysis.md` → "Step 3 — Log triage".
No identifiable fix → surface log and stop. **Never** blind-retry.

## Step 4: Fix Locally + Validate

Edit failing files per Step 3, then run the same lint/test command CI ran (NF-3
— CI infinite-loop guard; detection heuristic in `references/safety.md` → "Local
validation gate"). Still red → stop with `[FAIL] local checks failed — fix
before push`. **Do not push.**

## Step 5: Commit + Push (no force)

Inline commit (do NOT delegate to `gh:commit` — composition re-prompt). Title
`fix(ci): <summary> (#<PR_NUMBER>)`. Fast-forward push only — **no `--force`, no
`--force-with-lease`**. Rejected → surface divergence and stop; **label is NOT
yet removed**. Exact commands + divergence message: `references/safety.md` →
"Step 5 push".

**Immediately after a successful push**, drop a stale `review-passed` via the
shared `_gh_pr_drop_label` helper — **unconditional**, because a CI-fix commit
changes file content by definition, so the patch-id "keep" path that
`gh:pr-resolve-outdated` / `gh:pr-resolve-conflict` have can never apply here
(#1705). This runs **before** Step 6's `--wait`, not deferred to Step 7 —
`--wait` can poll for minutes with the head unchanged, and a re-review
completing in that window could grant a genuinely fresh `review-passed` for
this exact head; dropping before the wait starts closes that window entirely
(#1711 codex review). Never touches `review-blocked` (#1563). Soft-fail: one
`[WARN]` line, CI-fix success unaffected. Exact block: `references/safety.md`
→ "`review-passed` drop".

## Step 6: Optional CI Green Wait (`--wait`)

`--wait <seconds>` passed → poll `gh pr checks` (host-pinned, `--repo "$TARGET_REPO"`) every 30 s until green
or timeout. Timeout → `[WARN] CI still pending after <N>s — proceeding to label
removal.` Without flag, skip. Polling loop: `references/ci-log-analysis.md` →
"Step 6 — --wait polling loop".

## Step 7: Remove `CI fail` Label + Report

**Invariant** — last mutation. Step 5 push failed → this step does NOT run
(label stays so reviewers know CI is still red). Canonical label name from
`references/label-normalization.md`. Remove via REST DELETE (not `gh pr edit
--remove-label` — classic-Projects silent-fail, #326 Bug B); 404 = absent →
soft-fail. Full block + ai-metrics comment: `references/safety.md` → "Step 7".
(The `review-passed` drop is not here — see Step 5.)

Report: `[OK] PR #<N> CI 복구 완료 · 라벨 제거됨 · <sha> push 됨.` followed by
`Next: /gh-pr-reply <N>  # CI 그린 확인 후 리뷰어 회신`.

## Constraints

Full constraint list: [references/constraints.md](references/constraints.md)

## Related Skills

Same PR-lifecycle slot, different verb — `gh:pr-resolve-conflict` (rebase-resolve
file conflicts) · `gh:pr-resolve-outdated` (clean rebase when the base moved with
no conflicts). Full list: `references/help.md` → "Related skills".
