---
name: gh:issue-flow
description: >-
  Chain one GitHub issue to a reviewed PR: implement → commit → PR → review →
  rebase-sync. Use for /gh:issue-flow, /gh-issue-flow, "이슈 #16 처음부터 PR까지
  자동으로", "이슈 구현하고 PR까지 한방에", "full flow on #42". Takes an issue
  number, not a spec (devx:autopilot).
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "composite orchestration (implement→commit→PR→gate→reply→rebase); chain dispatcher with stop-on-error"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-flow — Issue → PR composition

## Role

이슈 번호 1건을 원자 스킬 6개(Step 2)로 체인 실행한다 — 구현은 **direct 모드 전용**
이고, plan/brainstorming 이 필요하면 `gh:issue-implement` 를 직접 부른다.
**첫 단계 실패에서 즉시 중단하고 재개 지침이 담긴 리포트를 낸다**(이후 단계 자동 스킵).
**전제조건**: 이미 전용 worktree 의 feature 브랜치 위에 있어야 한다.

## CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop after Step 2.x.** Three layered guards
prevent it — (1) `--no-next-hint` on Step 2.1, (2) zero conversational text
between the six `Skill()` calls in Step 2, (3) the harness guard on `Stop` +
`SubagentStop` (`claude/hooks/gh_issue_flow_stop_guard.py`, #1434). **Do not
remove any of them.** Only prose is forbidden between the calls; the gate is
delegated to Step 2.4. History (#333, #383): `references/critical-contract.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls. That file names the 6 chained
skills and what devx:pr-review-all runs as the post-PR quality gate.

## Step 1: Parse Args

Argument table (`<issue-number>`, `[remote]`, `-h`/`--help`/`help`):
`references/help.md`. No `mode` arg — implementation is always `direct`.
Record `START_TS=$(date +%s)` for elapsed-time tracking in Step 2.6.

**Bind the GitHub target once, here (#1403)** — resolve host and repo from the
`[remote]`'s URL and export `GH_HOST` / `TARGET_REPO` / `TARGET_HOST` before
Step 2. Since #1405 the binding is authoritative for the whole chain —
`[remote]` is threaded explicitly into 2.1 `gh:issue-implement`, 2.2
`gh:commit`, 2.3 `gh:pr` and 2.4 `devx:pr-review-all`. Exact block and the
reason the host is passed explicitly: `references/target-binding.md`.

## Step 2: Chain the Skills

Invoke in order; each runs only if the previous succeeded. **Zero
conversational text between the calls — no recap, headers, or progress
bullets** (see CRITICAL CONTRACT). After each call, proceed to the next.

1. **Step 2.1 — gh:issue-implement** — `--no-next-hint` is load-bearing.
   `Skill(gh:issue-implement, "<N> direct <remote> --no-next-hint")`
2. **Step 2.2 — gh:commit** (only if 2.1 succeeded) — `[remote]` pins the
   metrics/board target (#1405). `Skill(gh:commit, "<N> <remote>")`
3. **Step 2.3 — gh:pr** (only if 2.2 succeeded) — ensures `Closes #<N>`, pushes
   and opens the PR on `<remote>` (#1405); extract `<PR_NUM>` from the PR URL.
   `Skill(gh:pr, "<N> <remote>")`
4. **Step 2.4 — devx:pr-review-all** (only if 2.3 succeeded; soft-fail) — one
   delegated call runs the post-PR quality gate (agy ∥ codex ∥ `/simplify`),
   commits + pushes any simplify changes synchronously, and schedules
   `/gh-pr-reply <PR_NUM>` 4 min later via `--defer-reply`. The synchronous
   simplify commit lands before the 2.5/2.5.1 rebase steps. Detail:
   `references/quality-gate-step.md`.
   `Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 4")`
5. **Step 2.5 — gh:pr-resolve-conflict** (only if 2.4 succeeded) —
   rebase-resolve; a fresh PR usually prints "이미 충돌 없음 — skip".
   `Skill(gh:pr-resolve-conflict, "<PR_NUM>")`
6. **Step 2.5.1 — gh:pr-resolve-outdated** (only if 2.5 succeeded) — clean
   rebase-sync when the base moved forward with no conflicts; no-op if already
   up to date. `Skill(gh:pr-resolve-outdated, "<PR_NUM>")`
7. **Step 2.6 — Post AI Metrics to Issue** (only if 2.5.1 succeeded;
   soft-fail) — aggregate flow-level metrics comment on the linked Issue.
   Full procedure: `references/ai-metrics-step.md`.

## Step 3: Report

Output format (success/soft-fail/failure templates + resume-hint logic) is in
`references/report-template.md`. Always end with the `[OK]`/`[FAIL]`/`[SKIP]`
report as plain assistant text — never via `Bash` heredoc or `Write` (#1270).

## Constraints

See `references/constraints.md` for the full list (direct mode only, never
retry/skip a step, quality-gate + Step 2.6 soft-fail exceptions, the
simplify-commit-before-rebase rule, the early-stop guards, do-not-stop-mid-flow).

## Related Skills

Chained atoms: `gh:issue-implement` · `gh:commit` · `gh:pr` · `devx:pr-review-all`
· `gh:pr-resolve-conflict` · `gh:pr-resolve-outdated`. Spec-driven cousin: `devx:autopilot`.
