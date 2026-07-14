---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr →
  a parallel post-PR quality gate (codex review ∥ /simplify) → devx:schedule
  (pr-reply, 5 min) → gh:pr-resolve-conflict → gh:pr-resolve-outdated
  (out-of-date base sync) for a single issue number. Use when the user runs
  /gh:issue-flow, /gh-issue-flow, or asks "issue #16 처음부터 PR까지 자동으로",
  "이슈 구현하고 커밋하고 PR까지 한방에", "full flow on #42". Uses direct
  implementation mode only — for plan/brainstorming modes, use the atomic
  gh:issue-implement skill manually. Stops on first step failure with a
  resume-instructions report. Precondition: already on a feature branch in a
  dedicated worktree. Accepts `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "composite orchestration (implement→commit→PR→gate→reply→rebase); chain dispatcher with stop-on-error"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-flow — Issue → PR composition

## CRITICAL CONTRACT — read before editing

**Recurring failure mode: early-stop after Step 2.x.** Three layered guards
prevent it — (1) `--no-next-hint` on Step 2.1, (2) zero conversational text
between the six `Skill()` calls in Step 2, (3) the harness Stop hook
(`claude/hooks/gh_issue_flow_stop_guard.py`). **Do not remove any of them.**
Tool calls between Skill() calls are permitted — the Agent dispatch for the
2.3.1/2.3.2 quality gate and the Bash commit+push of 2.3.3 are fine; only
conversational prose (recaps, headers, bullets) is forbidden. Terminal-marker
gating in the hook covers those tool steps automatically. Full failure history
(#333, #383) and guard rationale: `references/critical-contract.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls. The help output names the 6
chained skills (gh:issue-implement, gh:commit, gh:pr, devx:schedule,
gh:pr-resolve-conflict, gh:pr-resolve-outdated) and the parallel post-PR
quality gate (codex review ∥ /simplify).

## Step 1: Parse Args

| Argument | Description | Default |
|----------|-------------|---------|
| `<issue-number>` | 처리할 GitHub Issue 번호 (양의 정수) | — |
| `[remote]` | git remote 이름 | `origin` |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

No `mode` arg — implementation is always `direct`. Record
`START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 2.6.

## Step 2: Chain the Skills

Invoke in order; each runs only if the previous succeeded. **Zero
conversational text between the calls — no recap, headers, or progress
bullets** (see CRITICAL CONTRACT). Tool calls for the quality gate are allowed;
prose is not. After each call, immediately proceed to the next.

1. **Step 2.1 — gh:issue-implement** — `--no-next-hint` is load-bearing.
   `Skill(gh:issue-implement, "<N> direct <remote> --no-next-hint")`
2. **Step 2.2 — gh:commit** (only if 2.1 succeeded) — auto-detects the issue
   number from the conversation. `Skill(gh:commit)`
3. **Step 2.3 — gh:pr** (only if 2.2 succeeded) — ensures `Closes #<N>`;
   extract `<PR_NUM>` from the PR URL. `Skill(gh:pr, "<N>")`
4. **Steps 2.3.1 ∥ 2.3.2 ∥ 2.3.3 — quality gate** (only if 2.3 succeeded;
   soft-fail). Dispatch 2.3.1 (codex review, if `command -v codex`) and 2.3.2
   (`/simplify`) as **two parallel Agent subagents in one turn**, then 2.3.3
   commits + pushes any simplify changes — this **must run before 2.5/2.5.1**
   (dirty tree breaks rebase). Detail: `references/quality-gate-step.md`.
5. **Step 2.4 — devx:schedule** (only if the gate finished) — schedules
   `/gh-pr-reply <PR_NUM>` 5 min after PR creation.
   `Skill(devx:schedule, "--time 5 \"/gh-pr-reply <PR_NUM>\"")`
6. **Step 2.5 — gh:pr-resolve-conflict** (only if 2.4 succeeded) —
   rebase-resolve; a fresh PR usually prints "이미 충돌 없음 — skip".
   `Skill(gh:pr-resolve-conflict, "<PR_NUM>")`
7. **Step 2.5.1 — gh:pr-resolve-outdated** (only if 2.5 succeeded) — clean
   rebase-sync when the base moved forward with no conflicts; no-op if already
   up to date. `Skill(gh:pr-resolve-outdated, "<PR_NUM>")`
8. **Step 2.6 — Post AI Metrics to Issue** (only if 2.5.1 succeeded;
   soft-fail) — aggregate flow-level metrics comment on the linked Issue.
   Full procedure: `references/ai-metrics-step.md`.

## Step 3: Report

Output format (success template, soft-fail variant, failure template, and
the per-step resume-hint logic) is defined in `references/report-template.md`.
Always end with the `[OK]`/`[FAIL]`/`[SKIP]` structured report.

## Constraints

See `references/constraints.md` for the full list (direct mode only, never
retry/skip a step, quality-gate + Step 2.6 soft-fail exceptions, the
simplify-commit-before-rebase rule, the `--no-next-hint` and zero-prose
early-stop guards, and the do-not-stop-mid-flow rule).
