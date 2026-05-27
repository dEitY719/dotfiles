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
  [[gh-pr-resolve-conflict]] — different verb and risk profile, same
  PR-lifecycle slot. Accepts `[pr-number] [remote] [--wait <seconds>]
  [--label-variant <input>]`; defaults to the PR attached to the current
  branch. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# gh:pr-resolve-ci-fail — CI Failure Resolution

## Help

Arg #1 `-h`/`--help`/`help` → read `references/help.md` verbatim, stop. No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for Step 7.

Positional: `[pr-number] [remote]`. Flags: `--wait <seconds>` (opt-in,
default off), `--label-variant <input>` (override canonical label).

- `pr-number` omitted → auto-detect via `gh pr view --json
  number,state,headRefName` on current branch. No PR → stop.
- `remote` default `origin`. Missing → `git remote -v` and stop.
- `--label-variant` normalized via `references/label-normalization.md`; unknown → fail-fast.

State `OPEN` required. Hard preconditions in `references/safety.md` →
"Preconditions". Capture `BACKUP_SHA=$(git rev-parse HEAD)` for recovery.

## Step 2: Fetch Failing Checks

### Pre-check — is `main` itself red?

본격 분석 전에 main 의 동일 workflow 가 inherited red 인지 1초 확인:

```bash
gh run list --repo "$TARGET_REPO" --branch main --workflow <workflow> --limit 3
```

세 run 중 2개 이상 failure 이고 PR run 과 동일 step 에서 fail 한다면
PR 회귀가 아닐 가능성이 높다 (#755 의 28건 bats fail 이 그 사례).
다음과 같이 stop — 라벨은 건드리지 않고 그대로 종료:

```
[STOP] main 자체가 적색입니다 (latest 3 runs: failure / failure / success).
       PR 회귀가 아니라 inherited red — main 먼저 회복하세요.
       Next: /gh-issue-create  # umbrella 또는 sub-issue 등록
```

False-positive: main 의 transient red (1회 fail, 직후 green) 은 무시하고
통상 절차 진행. 판정 기준·예시·예외 케이스 전체는
`references/ci-log-analysis.md` → "Step 2 — pre-check (is main red?)".

### Failing-check fetch

`gh pr checks <N> --required --json name,state,workflow,link`, filter
`state == FAILURE`. All green → `[OK] no failing checks — nothing to
resolve.` and stop. Filter rubric + in-progress carveout in
`references/ci-log-analysis.md` → "Step 2".

## Step 3: Fetch + Analyze Logs

Resolve each failing workflow's latest `RUN_ID`, dump `gh run view
<id> --log-failed`, identify the root cause. Parsing rubric +
common patterns (lint / type / test / build) in
`references/ci-log-analysis.md` → "Step 3 — Log triage". No
identifiable fix → surface log and stop. **Never** blind-retry.

## Step 4: Fix Locally + Validate

Edit failing files per Step 3, then run the same lint/test command CI
ran (NF-3 — CI infinite-loop guard; detection heuristic in
`references/safety.md` → "Local validation gate"). Still red → stop with
`[FAIL] local checks failed — fix before push`. **Do not push.**

## Step 5: Commit + Push (no force)

Inline commit (do NOT delegate to `gh:commit` — composition re-prompt).
Title `fix(ci): <summary> (#<PR_NUMBER>)`. Fast-forward push only —
**no `--force`, no `--force-with-lease`**. Rejected → surface
divergence and stop; **label is NOT yet removed**. Exact commands +
divergence message in `references/safety.md` → "Step 5 push".

## Step 6: Optional CI Green Wait (`--wait`)

`--wait <seconds>` passed → poll `gh pr checks --required` every 30 s
until green or timeout. Timeout → `[WARN] CI still pending after
<N>s — proceeding to label removal.` Without flag, skip. Polling loop
in `references/ci-log-analysis.md` → "Step 6 wait".

## Step 7: Remove `CI fail` Label + Report

**Invariant** — last mutation. Step 5 push failed → this step does NOT
run (label stays so reviewers know CI is still red). Canonical label
name from `references/label-normalization.md`.

REST DELETE: `gh api -X DELETE
"repos/{owner}/{repo}/issues/<N>/labels/CI%20fail"` (URL-encode space;
404 = absent → soft-fail). **Do not** use `gh pr edit --remove-label` —
classic-Projects silent-fail issue same as `gh:pr-resolve-conflict` Step
5 (#326 Bug B). Full block + ai-metrics comment in
`references/safety.md` → "Step 7".

Report: `[OK] PR #<N> CI 복구 완료 · 라벨 제거됨 · <sha> push 됨.`
followed by `Next: /gh-pr-reply <N>  # CI 그린 확인 후 리뷰어 회신`.

## Constraints

- Never `--force` / `--force-with-lease`. Fast-forward only.
- Never run on the default branch.
- Never push when local lint/test is red.
- Never remove the label before push succeeds.
- Never auto-create labels (missing label → soft-fail).
- Never auto-stash. Clean tree required.
- Never delegate to `gh:commit` (re-prompt inside composition).
