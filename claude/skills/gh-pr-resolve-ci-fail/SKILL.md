---
name: gh:pr-resolve-ci-fail
description: >-
  Resolve a GitHub PR's CI failure: fetch failing check logs, fix the cause
  locally, run local lint/test, commit and push (never force), then remove
  the `CI fail` label as the **last** step so reviewers can re-approve. Use
  when the user runs /gh:pr-resolve-ci-fail, /gh-pr-resolve-ci-fail, or asks
  "PR CI fail 해결", "CI fail 라벨 떼줘", "PR CI 빨간 거 고쳐". Refuses on the
  default branch, refuses `--force` / `--force-with-lease`, refuses to push
  when local lint/test is red (CI infinite-loop guard). Sister skill of
  [[gh-pr-resolve-conflict]] and [[gh-pr-resolve-outdated]] — same
  PR-lifecycle slot, different verb and risk profile. Accepts `[pr-number] [remote] [--wait <seconds>]
  [--label-variant <input>]`; defaults to the PR attached to the current
  branch. Accepts `-h`/`--help`/`help`.
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

- `pr-number` omitted → auto-detect via `gh pr view --json
  number,state,headRefName` on current branch. No PR → stop.
- `remote` default `origin`. Missing → `git remote -v` and stop. `--label-variant`
  normalized via `references/label-normalization.md`; unknown → fail-fast.

State `OPEN` required. Hard preconditions in `references/safety.md` →
"Preconditions". Capture `BACKUP_SHA=$(git rev-parse HEAD)` for recovery.

## Step 2: Fetch Failing Checks

Pre-check — main 의 동일 workflow 가 inherited red 인지 먼저 확인한다. 최신 3 run
중 2개 이상이 PR 과 동일 step 에서 fail 하면 inherited red — 라벨을 건드리지 않고
`[STOP]` 종료 (#755 사례). transient red(1회 fail 후 green)은 무시하고 진행.
명령·예제·판정 기준·예외: `references/ci-log-analysis.md` → "Pre-check (is main red?)".

### Failing-check fetch

`gh pr checks <N> --required --json name,state,workflow,link`, filter `state ==
FAILURE`. All green → `[OK] no failing checks — nothing to resolve.` and stop.
Filter rubric + in-progress carveout: `references/ci-log-analysis.md` → "Step 2 — Fetch failing checks".

## Step 3: Fetch + Analyze Logs

Resolve each failing workflow's latest `RUN_ID`, dump `gh run view <id>
--log-failed`, identify the root cause. Parsing rubric + common patterns (lint /
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

## Step 6: Optional CI Green Wait (`--wait`)

`--wait <seconds>` passed → poll `gh pr checks --required` every 30 s until green
or timeout. Timeout → `[WARN] CI still pending after <N>s — proceeding to label
removal.` Without flag, skip. Polling loop: `references/ci-log-analysis.md` →
"Step 6 — --wait polling loop".

## Step 7: Remove `CI fail` Label + Report

**Invariant** — last mutation. Step 5 push failed → this step does NOT run
(label stays so reviewers know CI is still red). Canonical label name from
`references/label-normalization.md`. Remove via REST DELETE (not `gh pr edit
--remove-label` — classic-Projects silent-fail, #326 Bug B); 404 = absent →
soft-fail. Full block + ai-metrics comment: `references/safety.md` → "Step 7".

Report: `[OK] PR #<N> CI 복구 완료 · 라벨 제거됨 · <sha> push 됨.` followed by
`Next: /gh-pr-reply <N>  # CI 그린 확인 후 리뷰어 회신`.

## Constraints

Never: `--force`/`--force-with-lease` (fast-forward only); run on the default
branch; push when local lint/test is red; remove the label before push
succeeds; auto-create labels (missing → soft-fail); auto-stash (clean tree
required); delegate to `gh:commit` (re-prompt inside composition).
